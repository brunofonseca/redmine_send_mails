#encoding: utf-8

require_dependency 'issues_controller'

module IssueSendParamPatch
    def self.included(base)
      base.send(:include, InstanceMethods)
      
      base.class_eval do
        alias_method_chain :update, :send_mail_checker_issues
        alias_method_chain :create, :send_mail_checker_issues
        alias_method_chain :bulk_update, :send_mail_checker_issues
      end
    end
end

module InstanceMethods
  def update_with_send_mail_checker_issues
    return unless update_issue_from_params
    @issue.save_attachments(params[:attachments] || (params[:issue] && params[:issue][:uploads]))
    saved = false
    begin
      @issue.set_mail_checker_issue(params[:mail_checker_issue])
      saved = @issue.save_issue_with_child_records(params, @time_entry)
    rescue ActiveRecord::StaleObjectError
      @conflict = true
      if params[:last_journal_id]
        if params[:last_journal_id].present?
          last_journal_id = params[:last_journal_id].to_i
          @conflict_journals = @issue.journals.all(:conditions => ["#{Journal.table_name}.id > ?", last_journal_id])
        else
          @conflict_journals = @issue.journals.all
        end
      end
    end

    if saved
      render_attachment_warning_if_needed(@issue)
      flash[:notice] = l(:notice_successful_update) unless @issue.current_journal.new_record?

      respond_to do |format|
        format.html { redirect_back_or_default({:action => 'show', :id => @issue}) }
        format.api  { head :ok }
      end
    else
      respond_to do |format|
        format.html { render :action => 'edit' }
        format.api  { render_validation_errors(@issue) }
      end
    end
  end
  
  def create_with_send_mail_checker_issues
    call_hook(:controller_issues_new_before_save, { :params => params, :issue => @issue })
    @issue.set_mail_checker_issue(params[:mail_checker_issue])
    @issue.save_attachments(params[:attachments] || (params[:issue] && params[:issue][:uploads]))
    if @issue.save
      call_hook(:controller_issues_new_after_save, { :params => params, :issue => @issue})
      respond_to do |format|
        format.html {
          render_attachment_warning_if_needed(@issue)
          flash[:notice] = l(:notice_issue_successful_create, :id => "<a href='#{issue_path(@issue)}'>##{@issue.id}</a>")
          redirect_to(params[:continue] ?  { :action => 'new', :project_id => @issue.project, :issue => {:tracker_id => @issue.tracker, :parent_issue_id => @issue.parent_issue_id}.reject {|k,v| v.nil?} } :
                      { :action => 'show', :id => @issue })
        }
        format.api  { render :action => 'show', :status => :created, :location => issue_url(@issue) }
      end
      return
    else
      respond_to do |format|
        format.html { render :action => 'new' }
        format.api  { render_validation_errors(@issue) }
      end
    end
  end

  def bulk_update_with_send_mail_checker_issues
    @issues.sort!
    @copy = params[:copy].present?
    attributes = parse_params_for_bulk_issue_attributes(params)

    unsaved_issue_ids = []
    moved_issues = []
    @issues.each do |issue|
      issue.reload
      if @copy
        issue = issue.copy({}, :attachments => params[:copy_attachments].present?)
      end
      journal = issue.init_journal(User.current, params[:notes])
      issue.safe_attributes = attributes
      call_hook(:controller_issues_bulk_edit_before_save, { :params => params, :issue => issue })
      issue.set_mail_checker_issue(params[:mail_checker_issue])
      if issue.save
        moved_issues << issue
      else
        # Keep unsaved issue ids to display them in flash error
        unsaved_issue_ids << issue.id
      end
    end
    set_flash_from_bulk_issue_save(@issues, unsaved_issue_ids)

    if params[:follow]
      if @issues.size == 1 && moved_issues.size == 1
        redirect_to :controller => 'issues', :action => 'show', :id => moved_issues.first
      elsif moved_issues.map(&:project).uniq.size == 1
        redirect_to :controller => 'issues', :action => 'index', :project_id => moved_issues.map(&:project).first
      end
    else
      redirect_back_or_default({:controller => 'issues', :action => 'index', :project_id => @project})
    end
  end


end

Rails.configuration.to_prepare do
  IssuesController.send(:include, IssueSendParamPatch)
end