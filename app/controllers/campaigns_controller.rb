class CampaignsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_campaign, only: [:show, :edit, :update, :destroy, :schedule, :send_now, :pause, :resume, :cancel, :send_test, :stats, :preview]

  # GET /campaigns
  def index
    @campaigns = current_account.campaigns.order(created_at: :desc)

    # Filter by status
    if params[:status].present?
      @campaigns = @campaigns.where(status: params[:status])
    end

    # Filter by list
    if params[:list_id].present?
      @campaigns = @campaigns.where(list_id: params[:list_id])
    end
  end

  # GET /campaigns/:id
  def show
    # Draft campaigns should be edited, not viewed
    if @campaign.draft?
      redirect_to edit_campaign_path(@campaign, step: 1)
      return
    end

    @recent_sends = @campaign.campaign_sends.includes(:subscriber).order(sent_at: :desc).limit(10)
  end

  # GET /campaigns/new
  def new
    @campaign = current_account.campaigns.new
    @lists = current_account.lists
    @templates = current_account.templates
    @custom_fields = current_account.custom_field_definitions.order(:name)
    @step = params[:step]&.to_i || 1
  end

  # POST /campaigns
  def create
    @campaign = current_account.campaigns.new(campaign_params)
    @lists = current_account.lists
    @templates = current_account.templates
    @custom_fields = current_account.custom_field_definitions.order(:name)
    @step = params.dig(:campaign, :step)&.to_i || params[:step]&.to_i || 1

    if @campaign.save
      # Always redirect to step 2 after creating (step 1)
      redirect_to edit_campaign_path(@campaign, step: 2), notice: "Campaign created. Now add your email content."
    else
      @step = 1
      render :new, status: :unprocessable_entity
    end
  end

  # GET /campaigns/:id/edit
  def edit
    unless @campaign.draft?
      redirect_to @campaign, alert: "Only draft campaigns can be edited."
      return
    end

    @lists = current_account.lists
    @templates = current_account.templates
    @custom_fields = current_account.custom_field_definitions.order(:name)
    @step = params[:step]&.to_i || 1
  end

  # PATCH/PUT /campaigns/:id
  def update
    unless @campaign.draft?
      redirect_to @campaign, alert: "Only draft campaigns can be edited."
      return
    end

    @lists = current_account.lists
    @templates = current_account.templates
    @custom_fields = current_account.custom_field_definitions.order(:name)
    @step = params.dig(:campaign, :step)&.to_i || params[:step]&.to_i || 1

    if @campaign.update(campaign_params)
      # Handle AJAX autosave requests (don't redirect)
      if request.xhr? || request.format.json?
        head :ok
        return
      end

      # Navigate through steps for form submissions
      if @step == 1
        redirect_to edit_campaign_path(@campaign, step: 2), notice: "Campaign details saved. Now add your email content."
      elsif @step == 2
        redirect_to edit_campaign_path(@campaign, step: 3), notice: "Content saved. Review your campaign before sending."
      else
        redirect_to @campaign, notice: "Campaign was successfully updated."
      end
    else
      if request.xhr? || request.format.json?
        render json: { errors: @campaign.errors.full_messages }, status: :unprocessable_entity
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end

  # DELETE /campaigns/:id
  def destroy
    @campaign.destroy
    redirect_to campaigns_url, notice: "Campaign was successfully deleted."
  end

  # POST /campaigns/:id/schedule
  def schedule
    scheduled_time = params[:scheduled_at].present? ? Time.parse(params[:scheduled_at]) : 1.hour.from_now

    if @campaign.schedule!(scheduled_time)
      redirect_to @campaign, notice: "Campaign scheduled for #{scheduled_time.strftime('%B %d, %Y at %I:%M %p')}."
    else
      redirect_to @campaign, alert: "Campaign could not be scheduled. Make sure it's in draft status."
    end
  end

  # POST /campaigns/:id/send_now
  def send_now
    if @campaign.start_sending!
      redirect_to @campaign, notice: "Campaign is now sending."
    else
      redirect_to @campaign, alert: "Campaign could not be sent. Make sure it's in draft or scheduled status."
    end
  end

  # POST /campaigns/:id/pause
  def pause
    if @campaign.pause!
      redirect_to @campaign, notice: "Campaign has been paused."
    else
      redirect_to @campaign, alert: "Only sending campaigns can be paused."
    end
  end

  # POST /campaigns/:id/resume
  def resume
    if @campaign.resume!
      redirect_to @campaign, notice: "Campaign has been resumed."
    else
      redirect_to @campaign, alert: "Only paused campaigns can be resumed."
    end
  end

  # POST /campaigns/:id/cancel
  def cancel
    if @campaign.cancel!
      redirect_to @campaign, notice: "Campaign has been cancelled."
    else
      redirect_to @campaign, alert: "Only draft or scheduled campaigns can be cancelled."
    end
  end

  # POST /campaigns/:id/send_test
  def send_test
    test_email = params[:test_email]

    if test_email.blank?
      redirect_to edit_campaign_path(@campaign, step: 3), alert: "Please provide a test email address."
      return
    end

    # Validate email format
    unless test_email.match?(URI::MailTo::EMAIL_REGEXP)
      redirect_to edit_campaign_path(@campaign, step: 3), alert: "Please provide a valid email address."
      return
    end

    # Validate campaign has content and template
    if @campaign.body_markdown.blank?
      redirect_to edit_campaign_path(@campaign, step: 3), alert: "Campaign must have content before sending a test."
      return
    end

    if @campaign.template.blank?
      redirect_to edit_campaign_path(@campaign, step: 3), alert: "Campaign must have a template before sending a test."
      return
    end

    # Enqueue test email job
    Campaigns::SendTestEmailJob.perform_later(@campaign.id, test_email)

    redirect_to edit_campaign_path(@campaign, step: 3), notice: "Test email is being sent to #{test_email}. Check your inbox in a moment."
  end

  # GET /campaigns/:id/preview
  def preview
    markdown_content = params[:content] || @campaign.body_markdown || ""

    # Store selected subscriber in session if provided
    if params[:subscriber_id].present?
      session[:preview_subscriber_id] = params[:subscriber_id]
    end

    begin
      # Get subscriber for merge tags (from session, param, or create sample)
      sample_subscriber = nil

      if session[:preview_subscriber_id].present?
        sample_subscriber = current_account.subscribers.find_by(id: session[:preview_subscriber_id])
      end

      sample_subscriber ||= if @campaign.list
        @campaign.list.subscribers.first || Subscriber.new(
          email: 'subscriber@example.com',
          custom_attributes: { 'name' => 'John Doe', 'first_name' => 'John', 'last_name' => 'Doe' }
        )
      else
        Subscriber.new(
          email: 'subscriber@example.com',
          custom_attributes: { 'name' => 'John Doe', 'first_name' => 'John', 'last_name' => 'Doe' }
        )
      end

      # Render the preview
      if @campaign.template
        # Create a temporary campaign object with the preview content
        preview_campaign = @campaign.dup
        preview_campaign.define_singleton_method(:body_markdown) { markdown_content }

        # Process merge tags in campaign content
        campaign_html = Mustache.render(
          Kramdown::Document.new(markdown_content).to_html,
          preview_campaign.send(:build_mustache_data, sample_subscriber)
        )

        # Build data for template with processed campaign content
        data = {
          content: campaign_html,
          body: campaign_html,
          email_content: campaign_html,
          email: sample_subscriber.email,
          subscriber_email: sample_subscriber.email,
          name: sample_subscriber.get_attribute("name"),
          first_name: sample_subscriber.get_attribute("first_name"),
          last_name: sample_subscriber.get_attribute("last_name"),
          campaign_name: preview_campaign.name,
          campaign_subject: preview_campaign.subject,
          campaign_from_name: preview_campaign.from_name,
          campaign_from_email: preview_campaign.from_email,
          account_name: current_account.name,
          logo_url: current_account.logo_url,
          unsubscribe_url: "#unsubscribe",
          current_year: Time.current.year
        }

        # Add custom attributes
        if sample_subscriber.custom_attributes.is_a?(Hash)
          sample_subscriber.custom_attributes.each do |key, value|
            data["custom_#{key}".to_sym] = value
          end
        end

        # Render template with data
        html = Mustache.render(@campaign.template.rendered_html, data)
        render html: html.html_safe, layout: false
      else
        # No template, process merge tags and render markdown
        data = @campaign.send(:build_mustache_data, sample_subscriber)
        html = Kramdown::Document.new(markdown_content).to_html
        html = Mustache.render(html, data)
        render html: html.html_safe, layout: false
      end
    rescue => e
      # In development, show the full error trace
      if Rails.env.development?
        render html: <<~HTML.html_safe, layout: false
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: monospace; padding: 20px; background: #f8d7da; color: #721c24; }
              h1 { font-size: 18px; margin-bottom: 10px; }
              pre { background: white; padding: 15px; border: 1px solid #f5c6cb; overflow-x: auto; }
              .error-class { color: #d9534f; font-weight: bold; }
              .error-message { margin: 10px 0; }
            </style>
          </head>
          <body>
            <h1>Preview Error (Development Mode)</h1>
            <div class="error-class">#{e.class.name}</div>
            <div class="error-message">#{e.message}</div>
            <pre>#{e.backtrace.join("\n")}</pre>
          </body>
          </html>
        HTML
      else
        # In production, show a simple error message
        render html: '<div style="padding: 20px; color: #dc3545;">Failed to load preview. Please check your campaign configuration.</div>'.html_safe, layout: false
      end
    end
  end

  # GET /campaigns/:id/stats
  def stats
    @stats = {
      total_recipients: @campaign.total_recipients,
      sent_count: @campaign.sent_count,
      delivered_count: @campaign.delivered_count,
      opened_count: @campaign.opened_count,
      clicked_count: @campaign.clicked_count,
      bounced_count: @campaign.bounced_count,
      complained_count: @campaign.complained_count,
      unsubscribed_count: @campaign.unsubscribed_count,
      failed_count: @campaign.failed_count,
      percent_complete: @campaign.percent_complete,
      open_rate: @campaign.open_rate,
      click_rate: @campaign.click_rate,
      bounce_rate: @campaign.bounce_rate,
      failure_rate: @campaign.failure_rate
    }

    @link_clicks = @campaign.campaign_links.order(click_count: :desc).limit(10)
  end

  # GET /campaigns/search_subscribers
  def search_subscribers
    query = params[:q]&.strip

    if query.blank?
      render json: []
      return
    end

    # Search subscribers by email or custom attributes
    subscribers = current_account.subscribers
                                 .where("email LIKE ?", "%#{query}%")
                                 .limit(10)

    results = subscribers.map do |subscriber|
      display_name = subscriber.custom_attributes&.dig('name') || subscriber.custom_attributes&.dig('first_name')
      display_name = "#{display_name} (#{subscriber.email})" if display_name
      display_name ||= subscriber.email

      {
        id: subscriber.id,
        email: subscriber.email,
        display: display_name
      }
    end

    render json: results
  end

  private

  def set_campaign
    @campaign = current_account.campaigns.find(params[:id])
  end

  def campaign_params
    params.require(:campaign).permit(
      :name,
      :subject,
      :from_name,
      :from_email,
      :reply_to_email,
      :list_id,
      :segment_id,
      :template_id,
      :body_markdown,
      :step
    )
  end

  def current_account
    @current_account ||= current_user.account
  end
  helper_method :current_account
end
