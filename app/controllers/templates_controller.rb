require 'ostruct'

class TemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_template, only: [:show, :edit, :update, :destroy, :preview]

  # GET /templates
  def index
    @templates = current_account.templates.order(created_at: :desc)
  end

  # GET /templates/:id
  def show
    @campaigns_using = @template.campaigns.order(created_at: :desc).limit(10)
  end

  # GET /templates/new
  def new
    @template = current_account.templates.new
  end

  # POST /templates
  def create
    @template = current_account.templates.new(template_params)

    if @template.save
      redirect_to @template, notice: "Template was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /templates/:id/edit
  def edit
  end

  # PATCH/PUT /templates/:id
  def update
    if @template.update(template_params)
      # Handle AJAX autosave requests (don't redirect)
      if request.xhr? || request.format.json?
        head :ok
        return
      end

      redirect_to @template, notice: "Template was successfully updated."
    else
      if request.xhr? || request.format.json?
        render json: { errors: @template.errors.full_messages }, status: :unprocessable_entity
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end

  # GET /templates/:id/preview
  def preview
    html_content = params[:content] || @template.html_content || ""

    begin
      # Create sample data for merge tags with rich content and varied image sizes
      sample_markdown = <<~MARKDOWN
        ![Wide Banner](https://placehold.co/1200x200/673AB7/white?text=Wide+Banner+Header)

        # Welcome to Our Newsletter

        Hi {{first_name}},

        We're excited to share this month's updates with you!

        ## Featured Stories

        ### Story 1: New Product Launch

        ![Small Icon](https://placehold.co/150x150/4CAF50/white?text=Icon)

        We're thrilled to announce our latest product. Here's what makes it special:

        - **Easy to use** - Intuitive interface designed for everyone
        - **Fast performance** - Lightning-quick response times
        - **Secure** - Enterprise-grade security built-in
        - **Affordable** - Pricing that fits any budget

        ![Product Hero Image](https://placehold.co/600x300/4CAF50/white?text=Product+Launch)

        ### Story 2: Customer Success

        See how our customers are achieving amazing results:

        1. Increased productivity by 50%
        2. Reduced costs by 30%
        3. Improved customer satisfaction scores
        4. Scaled to handle 10x more users

        ![Success Metrics Graph](https://placehold.co/700x350/2196F3/white?text=Success+Metrics)

        ## Featured Team Member

        ![Portrait Photo](https://placehold.co/250x400/9C27B0/white?text=Team+Member)

        Meet Sarah, our Customer Success Manager, who has helped over 500 companies achieve their goals.

        ## Quick Tips

        #### Tip #1: Get Started Fast
        Follow our quick-start guide to be up and running in minutes.

        #### Tip #2: Use Templates
        Save time with our pre-built templates.

        #### Tip #3: Automate Everything
        Set up workflows to automate repetitive tasks.

        ![Ultra-Wide Banner](https://placehold.co/1400x150/FF9800/white?text=Limited+Time+Offer)

        ## What's Next?

        - **Webinar** - Join us next Tuesday for a live demo
        - **Blog** - Check out our latest articles
        - **Support** - Our team is here to help 24/7

        ![Square Thumbnail](https://placehold.co/200x200/F44336/white?text=CTA)

        ---

        Thanks for being part of our community!

        Best regards,
        The {{account_name}} Team

        [Unsubscribe]({{unsubscribe_url}})
      MARKDOWN

      sample_campaign = OpenStruct.new(
        name: "Sample Campaign",
        subject: "Sample Subject",
        from_name: "Sample Sender",
        from_email: "sender@example.com",
        account: current_account,
        body_markdown: sample_markdown
      )

      sample_subscriber = Subscriber.new(
        email: 'subscriber@example.com',
        custom_attributes: { 'name' => 'John Doe', 'first_name' => 'John', 'last_name' => 'Doe' }
      )

      # Build sample data hash
      sample_content_html = Kramdown::Document.new(sample_campaign.body_markdown).to_html

      data = {
        content: sample_content_html,
        body: sample_content_html,
        email_content: sample_content_html,
        email: sample_subscriber.email,
        name: sample_subscriber.get_attribute("name"),
        first_name: sample_subscriber.get_attribute("first_name"),
        last_name: sample_subscriber.get_attribute("last_name"),
        custom_name: sample_subscriber.get_attribute("name"),
        custom_first_name: sample_subscriber.get_attribute("first_name"),
        custom_last_name: sample_subscriber.get_attribute("last_name"),
        campaign_name: sample_campaign.name,
        campaign_subject: sample_campaign.subject,
        account_name: current_account.name,
        logo_url: current_account.brand_logo.presence || "/logo-placeholder.png",
        unsubscribe_url: "#unsubscribe",
        current_year: Time.current.year
      }

      # Render with Mustache
      rendered_html = Mustache.render(html_content, data)

      render html: rendered_html.html_safe, layout: false
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
        render html: '<div style="padding: 20px; color: #dc3545;">Failed to load preview. Please check your template syntax.</div>'.html_safe, layout: false
      end
    end
  end

  # DELETE /templates/:id
  def destroy
    if @template.campaigns.exists?
      redirect_to @template, alert: "Cannot delete template that is being used by campaigns."
    else
      @template.destroy
      redirect_to templates_url, notice: "Template was successfully deleted."
    end
  end

  private

  def set_template
    @template = current_account.templates.find(params[:id])
  end

  def template_params
    params.require(:template).permit(
      :name,
      :description,
      :html_content,
      :markdown_content,
      :is_default
    )
  end

  def current_account
    @current_account ||= current_user.account
  end
  helper_method :current_account
end
