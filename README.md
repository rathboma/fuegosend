# FuegoMail 🔥

**High-performance email marketing platform for Amazon SES**

FuegoMail is a self-hosted email marketing SaaS built for teams who want full control over their email infrastructure. Bring your own AWS SES account, pay only for what you send, and get unlimited contacts with fixed-cost pricing.

## Features

### Email Marketing Core
- **Campaign Management**: Create, schedule, and send email campaigns to your lists
- **List Management**: Organize subscribers into unlimited lists and segments
- **Segmentation**: Dynamic segments with powerful filtering criteria
- **Template System**: Mustache-based templates with Markdown editor
- **Merge Tags**: Personalize emails with subscriber custom attributes
- **Subscription Forms**: Embeddable forms with double opt-in support
- **Image Management**: Upload and manage campaign images with CDN-friendly URLs

### Tracking & Analytics
- **Open Tracking**: Pixel-based email open tracking
- **Click Tracking**: Link click tracking with individual subscriber attribution
- **Campaign Statistics**: Real-time metrics (opens, clicks, bounces, complaints)
- **Subscriber Engagement**: Track individual subscriber activity across campaigns
- **Bounce & Complaint Handling**: Automatic processing of SES webhooks

### Risk Management & Deliverability
- **Smart Queueing**: 30-minute cooldown for Free plan campaigns (abuse prevention)
- **Canary Testing**: Automated quality checks for large campaigns (>500 recipients)
- **Kill-Switch**: Percentage-based bounce/complaint monitoring during sends
- **Domain Segmentation**: Tier-based tracking domains for reputation isolation
- **Plan-Based Throttling**: Different thresholds for Free vs Paid plans

### Multi-User & Collaboration
- **Team Management**: Invite team members with role-based access control
- **Roles**: Owner (full control), Admin (team + settings), Member (content only)
- **Invitation System**: Secure token-based invitations with email delivery
- **Permission System**: Granular permissions for team operations

### AWS SES Integration
- **Quota Monitoring**: Real-time SES quota tracking and display
- **Auto-Throttling**: Respects SES send rate limits automatically
- **Configuration Sets**: Optional SES Configuration Set support
- **Webhook Processing**: SNS webhook handling for bounces, complaints, deliveries
- **Multi-Region**: Support for all AWS SES regions

### Developer Experience
- **RESTful API**: Full-featured API with bearer token authentication
- **API Keys**: Generate and manage per-user API keys
- **Webhooks**: Outbound webhooks for campaign events (future)
- **CSV Import**: Bulk subscriber import with custom attributes
- **Background Jobs**: Solid Queue for reliable async processing

### UI/UX
- **Progress Indicators**: Real-time progress for large campaign preparation
- **Auto-Refresh**: Live updates during campaign sending
- **Responsive Design**: Bootstrap 5-based interface
- **Markdown Editor**: CodeMirror-powered side-by-side preview
- **Template Editor**: Live HTML preview with syntax highlighting

## Tech Stack

- **Framework**: Ruby on Rails 8.1.1
- **Database**: SQLite (production-ready with optimizations)
- **Authentication**: Devise
- **Background Jobs**: Solid Queue (database-backed, no Redis needed)
- **Asset Pipeline**: Propshaft (modern, fast asset serving)
- **Frontend**: Hotwire (Turbo + Stimulus), Bootstrap 5
- **Email Sending**: AWS SES via aws-sdk-sesv2
- **Markdown**: Kramdown
- **Template Engine**: Mustache
- **Encryption**: Rails Active Record Encryption (AWS credentials)

## Installation

### Prerequisites

- Ruby 3.3.6
- Node.js 18+ (for JavaScript build)
- SQLite 3.37+

### Setup

```bash
# Clone the repository
git clone <repository-url>
cd fuegomail

# Install dependencies
bundle install

# Setup database
bin/rails db:setup

# Start the server
bin/dev
```

The application will be available at http://localhost:3000

### Production Setup

```bash
# Install dependencies
bundle install

# Setup database
bin/rails db:create db:migrate

# Create initial admin user
bin/rails db:seed

# Precompile assets
bin/rails assets:precompile

# Start the server (use systemd or similar in production)
bin/rails server -e production
```

## Configuration

### Required Environment Variables

```bash
# Rails
SECRET_KEY_BASE=<generate with: bin/rails secret>
RAILS_MASTER_KEY=<from config/master.key or generate new>

# Active Record Encryption (for AWS credentials)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=<generate with: bin/rails db:encryption:init>
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=<generate with: bin/rails db:encryption:init>
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=<generate with: bin/rails db:encryption:init>

# URL Configuration
RAILS_FORCE_SSL=true # Production only
RAILS_HOSTS=your-domain.com # Production only
```

### AWS SES Setup

Each account needs their own AWS SES credentials:

1. Create IAM user with SES permissions
2. Configure in app at `/account/edit`:
   - AWS Region (e.g., us-east-1)
   - AWS Access Key ID
   - AWS Secret Access Key
   - Optional: SES Configuration Set Name

Required IAM permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail",
        "ses:GetSendQuota"
      ],
      "Resource": "*"
    }
  ]
}
```

### SNS Webhook Setup

For bounce/complaint tracking:

1. Create SNS topic in AWS
2. Subscribe to SES notifications (bounces, complaints, deliveries)
3. Add HTTPS subscription pointing to: `https://your-domain.com/webhooks/sns`
4. Confirm subscription via email

## Usage

### First Steps

1. **Login**: Visit `/users/sign_in`
   - Email: matthew@beekeeperstudio.io
   - Password: password (change immediately!)

2. **Configure AWS SES**: Go to Account Settings → Edit
   - Add your AWS credentials
   - Test the connection

3. **Create a List**: Lists → New List
   - Add your subscriber list

4. **Create a Template**: Templates → New Template
   - Use the Markdown or HTML editor

5. **Launch Campaign**: Campaigns → New Campaign
   - Select list, template, and content
   - Send immediately or schedule

### Inviting Team Members

1. Go to Team page (visible to Owners/Admins)
2. Enter email and select role
3. Team member receives invitation email
4. They create account via invitation link

### API Usage

Generate an API key in the dashboard, then:

```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
     https://your-domain.com/api/v1/subscribers
```

See `/pages/docs` for full API documentation.

## Development

### Running Tests

```bash
bin/rails test
```

### Background Jobs

Solid Queue runs in-process in development. In production, run as a separate process:

```bash
bin/jobs
```

### Database Console

```bash
bin/rails dbconsole
```

### Rails Console

```bash
bin/rails console
```

## Architecture

### Key Models

- **Account**: Multi-tenant organization (subdomain-based)
- **User**: Team members with role-based permissions
- **List**: Subscriber lists
- **Subscriber**: Email addresses with custom attributes
- **Segment**: Dynamic subscriber groups with filtering
- **Campaign**: Email campaigns with templates and content
- **CampaignSend**: Individual email send records (one per recipient)
- **Template**: Reusable email templates (Mustache)
- **Invitation**: Team member invitation system

### Background Jobs

- **Campaigns::EnqueueSendingJob**: Queues individual emails for sending
- **Campaigns::SendEmailJob**: Sends individual emails via SES
- **Campaigns::CreateCampaignSendsJob**: Async campaign send record creation
- **RiskManagement::ProcessQueuedCampaignJob**: Processes sandbox workflow
- **RiskManagement::AnalyzeCanaryCampaignJob**: Analyzes canary test results
- **RiskManagement::MonitorActiveCampaignsJob**: Kill-switch monitoring
- **RefreshSegmentCountsJob**: Refreshes stale segment counts

### Request Flow

1. User creates campaign
2. Campaign enters queue (Free plan: 30min cooldown)
3. Campaign sends created (async for >1000 recipients)
4. Canary testing for large campaigns (>500 recipients)
5. Full send begins with SES throttling
6. Webhooks process bounces/complaints/deliveries
7. Stats updated in real-time

## Deployment

### Recommended Stack

- **Server**: Ubuntu 22.04 LTS
- **Ruby**: rbenv or asdf
- **Process Manager**: systemd
- **Reverse Proxy**: Nginx
- **SSL**: Let's Encrypt
- **Monitoring**: Application-level logging

### systemd Service Example

```ini
[Unit]
Description=FuegoMail Web Server
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/fuegomail
Environment=RAILS_ENV=production
ExecStart=/home/deploy/.rbenv/shims/bundle exec rails server
Restart=always

[Install]
WantedBy=multi-user.target
```

### Nginx Configuration

```nginx
upstream fuegomail {
  server 127.0.0.1:3000;
}

server {
  listen 80;
  server_name your-domain.com;
  return 301 https://$server_name$request_uri;
}

server {
  listen 443 ssl http2;
  server_name your-domain.com;

  ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

  location / {
    proxy_pass http://fuegomail;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

## Contributing

This is an internal tool. Contact matthew@beekeeperstudio.io for access.

## License

Proprietary - All rights reserved

## Support

For issues or questions, contact: matthew@beekeeperstudio.io

---

Built with ❤️ for high-volume email marketers who want control and transparency.
