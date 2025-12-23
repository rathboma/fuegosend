class Template < ApplicationRecord
  belongs_to :account
  has_many :campaigns, dependent: :nullify

  validates :name, presence: true

  # Convert markdown to HTML if needed
  def rendered_html
    if html_content.present?
      html_content
    elsif markdown_content.present?
      markdown_to_html(markdown_content)
    else
      ""
    end
  end

  # Apply merge tags to template using Mustache
  def render_for(subscriber, campaign)
    template_content = rendered_html
    data = build_mustache_data(subscriber, campaign)

    # Render using Mustache
    Mustache.render(template_content, data)
  end

  private

  def markdown_to_html(markdown)
    Kramdown::Document.new(markdown).to_html
  end

  def build_mustache_data(subscriber, campaign)
    account = campaign.account

    # Render campaign markdown content to HTML
    campaign_content = if campaign.body_markdown.present?
      Kramdown::Document.new(campaign.body_markdown).to_html
    else
      ""
    end

    {
      # Campaign content to merge into template
      content: campaign_content,
      body: campaign_content,
      email_content: campaign_content,

      # Subscriber data
      email: subscriber.email,
      subscriber_email: subscriber.email,

      # Custom attributes (flatten for easier access)
      name: subscriber.get_attribute("name"),
      first_name: subscriber.get_attribute("first_name"),
      last_name: subscriber.get_attribute("last_name"),

      # Campaign data
      campaign_name: campaign.name,
      campaign_subject: campaign.subject,
      campaign_from_name: campaign.from_name,
      campaign_from_email: campaign.from_email,

      # Account data
      account_name: account.name,
      logo_url: account.brand_logo.presence || "/logo-placeholder.png",

      # URLs
      unsubscribe_url: "#unsubscribe", # This will be implemented with proper routes

      # Other
      current_year: Time.current.year
    }.merge(flatten_custom_attributes(subscriber))
  end

  # Flatten custom attributes for Mustache access
  # Converts subscriber.custom_attributes = {company: "Acme"} to {custom_company: "Acme"}
  def flatten_custom_attributes(subscriber)
    return {} unless subscriber.custom_attributes.is_a?(Hash)

    subscriber.custom_attributes.transform_keys { |key| "custom_#{key}".to_sym }
  end
end
