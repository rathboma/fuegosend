# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Production seeds - create default admin account
if Rails.env.production?
  puts "Seeding production data..."

  # Create admin account
  account = Account.find_or_create_by!(subdomain: "beekeeper") do |a|
    a.name = "Beekeeper Studio"
    a.aws_region = "us-east-1"
    a.active = true
    a.plan = "agency"
  end
  puts "✓ Created account: #{account.name}"

  # Create admin user
  user = User.find_or_create_by!(email: "matthew@beekeeperstudio.io") do |u|
    u.account = account
    u.password = "password"
    u.password_confirmation = "password"
    u.first_name = "Matthew"
    u.last_name = "Rathbone"
    u.role = "owner"
  end
  puts "✓ Created admin user: #{user.email}"
  puts "  ⚠️  Default password: 'password' - Please change this immediately after first login!"

  puts "\n✅ Production seeding complete!"
  puts "\nSign in at: https://your-domain.com/users/sign_in"
  puts "  Email: matthew@beekeeperstudio.io"
  puts "  Password: password (CHANGE THIS!)"
  puts ""
end

# Only seed in development environment
if Rails.env.development?
  puts "Seeding development data..."

  # Create demo account
  account = Account.find_or_create_by!(subdomain: "demo") do |a|
    a.name = "Demo Account"
    a.aws_region = "us-east-1"
    a.ses_max_send_rate = 14
    a.ses_max_24_hour_send = 200
    a.ses_sent_last_24_hours = 0
    a.active = true
  end
  puts "✓ Created demo account: #{account.name}"

  # Create demo user
  user = User.find_or_create_by!(email: "matthew.rathbone@gmail.com") do |u|
    u.account = account
    u.password = "password"
    u.password_confirmation = "password"
    u.first_name = "Matthew"
    u.last_name = "Rathbone"
    u.role = "owner"
  end
  puts "✓ Created demo user: #{user.email} (password: password)"

  # Create a sample list
  list = account.lists.find_or_create_by!(name: "Newsletter Subscribers") do |l|
    l.description = "Main newsletter list"
    l.enable_subscription_form = true
    l.double_opt_in = false
  end
  puts "✓ Created sample list: #{list.name}"

  # Create some sample subscribers
  5.times do |i|
    subscriber = account.subscribers.find_or_create_by!(email: "subscriber#{i + 1}@example.com") do |s|
      s.status = "active"
      s.source = "seed"
      s.confirmed_at = Time.current
      s.custom_attributes = {
        "name" => "Subscriber #{i + 1}",
        "company" => "Company #{i + 1}"
      }
    end

    # Add to list
    list.add_subscriber(subscriber) unless subscriber.lists.include?(list)
  end
  puts "✓ Created 5 sample subscribers"

  # Create a sample template
  template = account.templates.find_or_create_by!(name: "Basic Newsletter") do |t|
    t.description = "Professional newsletter template with branding"
    t.html_content = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body {
              margin: 0;
              padding: 0;
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
              line-height: 1.6;
              color: #333;
              background-color: #f4f4f4;
            }
            .email-wrapper {
              width: 100%;
              background-color: #f4f4f4;
              padding: 40px 0;
            }
            .email-container {
              max-width: 600px;
              margin: 0 auto;
            }
            .brand-logo {
              text-align: center;
              margin-bottom: 20px;
            }
            .brand-logo img {
              max-width: 200px;
              height: auto;
            }
            .email-card {
              background-color: #ffffff;
              border-radius: 8px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
              padding: 40px;
            }
            .email-content {
              color: #333;
            }
            .email-content h1 {
              color: #4CAF50;
              margin-top: 0;
              font-size: 28px;
            }
            .email-content h2 {
              color: #333;
              font-size: 22px;
            }
            .email-content p {
              margin: 16px 0;
            }
            .email-content a {
              color: #4CAF50;
              text-decoration: none;
            }
            .email-content a:hover {
              text-decoration: underline;
            }
            .email-footer {
              margin-top: 30px;
              padding-top: 30px;
              border-top: 1px solid #e0e0e0;
              text-align: center;
              font-size: 12px;
              color: #666;
            }
            .footer-links {
              margin: 15px 0;
            }
            .footer-links a {
              color: #666;
              text-decoration: none;
              margin: 0 10px;
            }
            .footer-links a:hover {
              text-decoration: underline;
            }
            .footer-address {
              margin-top: 15px;
              line-height: 1.4;
            }
          </style>
        </head>
        <body>
          <div class="email-wrapper">
            <div class="email-container">
              <!-- Brand Logo -->
              <div class="brand-logo">
                <img src="{{logo_url}}" alt="Logo">
              </div>

              <!-- Email Card -->
              <div class="email-card">
                <div class="email-content">
                  {{{content}}}
                </div>

                <!-- Footer -->
                <div class="email-footer">
                  <div class="footer-links">
                    <a href="{{unsubscribe_url}}">Unsubscribe</a>
                    •
                    <a href="#">Update Preferences</a>
                    •
                    <a href="#">View in Browser</a>
                  </div>
                  <div class="footer-address">
                    {{account_name}}<br>
                    You're receiving this email because you subscribed to our newsletter.<br>
                    © {{current_year}} All rights reserved.
                  </div>
                </div>
              </div>
            </div>
          </div>
        </body>
      </html>
    HTML
    t.is_default = true
  end
  puts "✓ Created sample template: #{template.name}"

  # Create a sample campaign (draft)
  campaign = account.campaigns.find_or_create_by!(name: "Welcome Campaign") do |c|
    c.list = list
    c.template = template
    c.subject = "Welcome to our newsletter!"
    c.from_name = "Demo Sender"
    c.from_email = "sender@example.com"
    c.body_markdown = "# Welcome!\n\nThanks for subscribing to our newsletter. We're excited to have you on board!\n\nBest regards,\nThe Team"
    c.status = "draft"
  end
  puts "✓ Created sample campaign: #{campaign.name}"

  puts "\n✅ Seeding complete!"
  puts "\nYou can sign in with:"
  puts "  Email: matthew.rathbone@gmail.com"
  puts "  Password: password"
  puts ""
end
