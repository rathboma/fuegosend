# FuegoMail Development Guide for AI Agents

This document provides comprehensive guidance for AI agents working on the FuegoMail codebase. It covers architecture, patterns, conventions, and workflows specific to this project.

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture Principles](#architecture-principles)
3. [Model Relationships](#model-relationships)
4. [Background Job Patterns](#background-job-patterns)
5. [Multi-Tenancy](#multi-tenancy)
6. [Campaign Workflow](#campaign-workflow)
7. [Risk Management System](#risk-management-system)
8. [Email Tracking](#email-tracking)
9. [Team & Permissions](#team--permissions)
10. [AWS SES Integration](#aws-ses-integration)
11. [Database Patterns](#database-patterns)
12. [Testing Approach](#testing-approach)
13. [Common Development Tasks](#common-development-tasks)
14. [Code Patterns & Conventions](#code-patterns--conventions)
15. [Gotchas & Important Considerations](#gotchas--important-considerations)

---

## Project Overview

FuegoMail is a self-hosted email marketing SaaS platform built with Ruby on Rails 8.1.1. It's designed for teams who want full control over their email infrastructure using Amazon SES.

**Key Technologies:**
- Rails 8.1.1 with modern conventions
- SQLite (production-ready, optimized)
- Solid Queue (database-backed background jobs, no Redis)
- Hotwire (Turbo + Stimulus)
- Bootstrap 5 (responsive UI)
- AWS SES via aws-sdk-sesv2
- Active Record Encryption (for AWS credentials)

**Philosophy:**
- Production-ready with minimal infrastructure
- No Redis dependency (Solid Queue uses database)
- Multi-tenant with subdomain-based account isolation
- Bring-your-own-AWS-SES model
- Risk management first (protect sender reputation)

---

## Architecture Principles

### 1. Multi-Tenant by Design

Every resource (lists, subscribers, campaigns, etc.) belongs to an `Account`. All queries MUST be scoped by account to prevent data leakage.

**Pattern:**
```ruby
# Good - scoped by current account
current_account.campaigns.find(params[:id])

# Bad - global query (security issue!)
Campaign.find(params[:id])
```

### 2. Subdomain-Based Routing

Each account has a unique subdomain. The `AccountsController` concern handles account resolution from subdomain.

**Implementation:**
```ruby
# app/controllers/concerns/accounts_controller.rb
def current_account
  @current_account ||= Account.find_by!(subdomain: request.subdomain)
end
```

### 3. Background Job Processing

All long-running operations use Solid Queue jobs:
- Campaign sending
- Email queue creation
- Risk management checks
- Segment refresh
- SNS webhook processing

**Pattern:**
```ruby
# Enqueue immediately
MyJob.perform_later(arg1, arg2)

# Enqueue for later
MyJob.set(wait: 30.minutes).perform_later(arg1, arg2)

# Enqueue at specific time
MyJob.set(wait_until: scheduled_time).perform_later(arg1, arg2)
```

### 4. Percentage-Based Thresholds

Risk management uses percentage-based thresholds, NOT static numbers:
- Free plan: 8% bounce OR 0.5% complaint
- Paid plans: 15% bounce OR 1% complaint
- Minimum 50 emails sent before checking

### 5. Async UI with Auto-Refresh

Long operations provide real-time progress using:
- Stimulus auto-refresh controller
- Progress tracking in database
- Auto-refresh at appropriate intervals (2-5s)

---

## Model Relationships

### Core Models

```
Account (tenant)
├── Users (team members)
├── Invitations (pending team members)
├── Lists (subscriber lists)
├── Subscribers (email addresses)
├── Segments (dynamic groups)
├── Campaigns (email campaigns)
├── Templates (email templates)
├── Images (uploaded images)
└── ApiKeys (API authentication)

Campaign
├── belongs_to :account
├── belongs_to :list
├── belongs_to :segment (optional)
├── belongs_to :template (optional)
└── has_many :campaign_sends

CampaignSend (individual email record)
├── belongs_to :campaign
├── belongs_to :subscriber
└── has_many :click_events

Subscriber
├── belongs_to :account
├── has_many :list_memberships
├── has_many :lists (through: :list_memberships)
└── has_many :campaign_sends
```

### Key Model Responsibilities

**Account:**
- Multi-tenant root
- AWS SES credentials (encrypted)
- SES quota tracking
- Plan enforcement (free vs paid)

**Campaign:**
- Email campaign orchestration
- Status state machine
- Risk management checks
- Progress tracking
- Stats aggregation

**CampaignSend:**
- Individual email tracking
- Status: pending → sent → delivered/bounced/complained
- Open/click tracking
- Bounce/complaint details

**Subscriber:**
- Email address + custom attributes (JSONB)
- Status: active, unsubscribed, bounced, complained
- Source tracking
- Double opt-in support

**Segment:**
- Dynamic subscriber filtering
- Cached counts with refresh job
- JSON-based filter criteria

---

## Background Job Patterns

### Campaign Sending Jobs

**Campaigns::CreateCampaignSendsJob**
- Purpose: Create CampaignSend records for each recipient
- When: Campaign enters sending state with >1000 recipients
- Progress: Updates `sends_created_count` and `preparation_progress` every 100 records
- Location: `app/jobs/campaigns/create_campaign_sends_job.rb`

**Campaigns::EnqueueSendingJob**
- Purpose: Queue individual emails for sending
- When: After campaign_sends created, campaign approved
- Throttling: Respects SES send rate limits
- Location: `app/jobs/campaigns/enqueue_sending_job.rb`

**Campaigns::SendEmailJob**
- Purpose: Send individual email via SES
- When: Enqueued by EnqueueSendingJob
- Tracking: Inserts tracking pixel and link tracking
- Error handling: Updates CampaignSend status on failure
- Location: `app/jobs/campaigns/send_email_job.rb`

### Risk Management Jobs

**RiskManagement::ProcessQueuedCampaignJob**
- Purpose: Handle Free plan 30-minute cooldown
- When: Campaign status = queued_for_review
- Workflow: Waits 30min → Approves campaign → Starts sending
- Location: `app/jobs/risk_management/process_queued_campaign_job.rb`

**RiskManagement::AnalyzeCanaryCampaignJob**
- Purpose: Analyze canary test results for large campaigns
- When: Campaign status = canary_processing, 10 minutes after canary start
- Checks: Bounce rate < 8%, complaint rate < 0.5%
- Actions: Approve or suspend campaign
- Location: `app/jobs/risk_management/analyze_canary_campaign_job.rb`

**RiskManagement::MonitorActiveCampaignsJob**
- Purpose: Kill-switch monitoring during sends
- When: Runs every 2 minutes via cron
- Checks: Percentage-based bounce/complaint rates
- Actions: Suspends campaign if thresholds exceeded
- Location: `app/jobs/risk_management/monitor_active_campaigns_job.rb`

### Other Jobs

**RefreshSegmentCountsJob**
- Purpose: Refresh stale segment counts
- When: Segment count_updated_at > 1 hour old
- Location: `app/jobs/refresh_segment_counts_job.rb`

---

## Multi-Tenancy

### Account Resolution

Every request resolves the account from subdomain:

```ruby
# app/controllers/application_controller.rb
before_action :set_current_account

def set_current_account
  @current_account = Account.find_by!(subdomain: request.subdomain)
end
```

### Scoping Queries

**ALWAYS scope by account:**

```ruby
# Controllers
def index
  @campaigns = current_account.campaigns.order(created_at: :desc)
end

def show
  @campaign = current_account.campaigns.find(params[:id])
end

# Models (when accessing associations)
campaign = current_account.campaigns.find(params[:id])
subscribers = campaign.list.subscribers # Already scoped via campaign → list → account
```

### Subdomain Configuration

Development environments support:
- `localhost` (default account)
- `demo.localhost:3000` (demo account)
- Custom subdomains via `/etc/hosts`

Production uses real subdomains:
- `beekeeper.fuegomail.com`
- `acme.fuegomail.com`

---

## Campaign Workflow

### Status State Machine

```
draft → scheduled → queued_for_review → canary_processing → approved → sending → completed
                                                                              ↓
                                                                          suspended
                                                                              ↓
                                                                           paused
```

**Status Definitions:**

1. **draft**: Being created/edited
2. **scheduled**: Set to send at future time
3. **queued_for_review**: Free plan 30-minute cooldown
4. **canary_processing**: Sending test batch (>500 recipients)
5. **approved**: Canary passed, ready to send
6. **sending**: Actively sending emails
7. **paused**: Manually paused by user
8. **suspended**: Automatically suspended by kill-switch
9. **completed**: All emails sent

### Workflow Steps

**1. Campaign Creation (draft)**
```ruby
campaign = account.campaigns.create!(
  name: "Newsletter",
  list: list,
  template: template,
  subject: "Subject",
  from_name: "Sender",
  from_email: "sender@example.com",
  body_markdown: "Content",
  status: "draft"
)
```

**2. Send Now (triggers workflow)**
```ruby
# app/models/campaign.rb
def send_now!
  # Determine recipients
  update!(
    total_recipients: recipients.count,
    started_sending_at: Time.current
  )

  # Check if large campaign (>1000)
  if total_recipients > 1000
    # Async send creation with progress
    create_campaign_sends_async!
  else
    # Sync send creation
    create_campaign_sends!
  end

  # Check plan and campaign size
  if account.plan_free?
    # Free plan → 30 minute queue
    update!(status: "queued_for_review", queued_at: Time.current)
    RiskManagement::ProcessQueuedCampaignJob.set(wait: 30.minutes).perform_later(id)
  elsif total_recipients > 500
    # Large campaign → canary test
    start_canary_test!
  else
    # Small campaign → immediate send
    approve_and_send!
  end
end
```

**3. Create Campaign Sends**
```ruby
# Creates individual CampaignSend record for each recipient
recipients.each do |subscriber|
  campaign_sends.create!(subscriber: subscriber, status: "pending")
end
```

**4. Risk Management Checks**

Free Plan Queue (30 min):
```ruby
# After 30 minutes
campaign.reload
if campaign.queued_for_review?
  campaign.approve_and_send!
end
```

Canary Test (>500 recipients):
```ruby
# Send to first 50 recipients
canary_sends = campaign_sends.limit(50)
canary_sends.each { |send| Campaigns::SendEmailJob.perform_later(send.id) }

# Wait 10 minutes
RiskManagement::AnalyzeCanaryCampaignJob.set(wait: 10.minutes).perform_later(campaign.id)

# Analyze results
if bounce_rate < 8% && complaint_rate < 0.5%
  campaign.approve_and_send!
else
  campaign.suspend_campaign!("High bounce/complaint rate in canary test")
end
```

**5. Send Campaign**
```ruby
# app/jobs/campaigns/enqueue_sending_job.rb
campaign.campaign_sends.where(status: "pending").find_each do |send|
  Campaigns::SendEmailJob.perform_later(send.id)

  # Throttle based on SES limits
  sleep(1.0 / account.ses_max_send_rate)
end
```

**6. Send Individual Email**
```ruby
# app/jobs/campaigns/send_email_job.rb
def perform(campaign_send_id)
  send_record = CampaignSend.find(campaign_send_id)

  # Render HTML with tracking
  html_body = render_email_with_tracking(send_record)

  # Send via SES
  ses_client.send_email({
    destination: { to_addresses: [send_record.subscriber.email] },
    content: {
      simple: {
        subject: { data: send_record.campaign.subject },
        body: { html: { data: html_body } }
      }
    }
  })

  # Update status
  send_record.update!(status: "sent", sent_at: Time.current)
end
```

**7. Kill-Switch Monitoring**
```ruby
# Runs every 2 minutes
Campaign.where(status: "sending").each do |campaign|
  campaign.check_kill_switch!
end

# In campaign model
def check_kill_switch!
  return false unless sending?
  return false if sent_count < 50 # Minimum sample size

  bounce_rate = (bounced_count.to_f / sent_count * 100).round(2)
  complaint_rate = (complained_count.to_f / sent_count * 100).round(2)

  if account.plan_free?
    if bounce_rate > 8.0 || complaint_rate > 0.5
      suspend_campaign!("Emergency stop: High bounce/complaint rate")
      return true
    end
  else
    if bounce_rate > 15.0 || complaint_rate > 1.0
      suspend_campaign!("Emergency stop: High bounce/complaint rate")
      return true
    end
  end

  false
end
```

---

## Risk Management System

FuegoMail implements multiple layers of risk management to protect sender reputation.

### 1. Smart Queueing (Free Plan)

**Purpose**: Prevent abuse on free tier
**Mechanism**: 30-minute cooldown before sending
**Implementation**:
```ruby
if account.plan_free?
  campaign.update!(status: "queued_for_review", queued_at: Time.current)
  RiskManagement::ProcessQueuedCampaignJob.set(wait: 30.minutes).perform_later(campaign.id)
end
```

### 2. Canary Testing (>500 Recipients)

**Purpose**: Test email quality on small batch before full send
**Mechanism**: Send to first 50 recipients, wait 10 minutes, analyze
**Thresholds**: <8% bounce, <0.5% complaint
**Implementation**: `RiskManagement::AnalyzeCanaryCampaignJob`

### 3. Kill-Switch Monitoring (During Sends)

**Purpose**: Stop campaigns with high bounce/complaint rates
**Mechanism**: Check every 2 minutes during active sends
**Thresholds**:
- Free plan: 8% bounce OR 0.5% complaint
- Paid plans: 15% bounce OR 1% complaint
**Minimum**: 50 emails sent before checking
**Implementation**: `RiskManagement::MonitorActiveCampaignsJob`

### 4. Bounce/Complaint Suppression

**Purpose**: Auto-unsubscribe bounced/complained subscribers
**Mechanism**: SNS webhook processing
**Actions**:
- Hard bounce → status = bounced, unsubscribe from all lists
- Complaint → status = complained, unsubscribe from all lists
**Implementation**: `WebhooksController#sns`

### 5. Plan-Based Limits (Free Plan)

**Limits**:
- 1 list maximum
- 1 segment maximum
- No import throttling (removed per user feedback)

**Enforcement**: UI-level (disabled buttons, warnings)

---

## Email Tracking

### Open Tracking

**Mechanism**: 1x1 transparent tracking pixel
**URL**: `/t/o/:token`
**Token**: Encrypted campaign_send_id
**Implementation**:
```ruby
# Insert into HTML body
tracking_pixel = "<img src='#{track_open_url(campaign_send.tracking_token)}' width='1' height='1' />"

# Controller
def open
  campaign_send = CampaignSend.find_by_tracking_token(params[:token])
  campaign_send.mark_opened! unless campaign_send.opened?
  send_data TRACKING_GIF, type: 'image/gif', disposition: 'inline'
end
```

### Click Tracking

**Mechanism**: Replace all links with tracking URLs
**URL**: `/t/c/:token`
**Token**: Encrypted data (campaign_send_id + original_url)
**Implementation**:
```ruby
# Replace links in HTML
html.gsub!(/<a\s+href="([^"]+)"/) do |match|
  original_url = $1
  tracking_url = track_click_url(generate_click_token(campaign_send, original_url))
  match.gsub(original_url, tracking_url)
end

# Controller
def click
  data = decrypt_click_token(params[:token])
  campaign_send = CampaignSend.find(data[:campaign_send_id])
  campaign_send.click_events.create!(url: data[:url], clicked_at: Time.current)
  redirect_to data[:url], allow_other_host: true
end
```

### Unsubscribe Links

**URL**: `/unsubscribe/:token`
**Token**: Encrypted subscriber_id
**Implementation**:
```ruby
# In email template
<a href="{{unsubscribe_url}}">Unsubscribe</a>

# Mustache helper provides
unsubscribe_url = unsubscribe_url(subscriber.unsubscribe_token)

# Controller
def unsubscribe
  @subscriber = Subscriber.find_by_unsubscribe_token(params[:token])
end

def unsubscribe_confirm
  @subscriber = Subscriber.find_by_unsubscribe_token(params[:token])
  @subscriber.unsubscribe!
  redirect_to root_path, notice: "You've been unsubscribed."
end
```

---

## Team & Permissions

### User Roles

**Owner**: Full control
- Manage team members
- Manage account settings
- Manage billing
- All content operations

**Admin**: Team + settings
- Manage team members
- Manage account settings
- All content operations
- Cannot manage billing

**Member**: Content only
- Create/edit lists, campaigns, subscribers
- Cannot manage team
- Cannot manage settings

### Role Checks

```ruby
# In User model
def owner?
  role == "owner"
end

def can_manage_team?
  owner? || admin?
end

def can_manage_account_settings?
  owner? || admin?
end

def can_manage_billing?
  owner?
end

# In controllers
before_action :require_team_management, only: [:team_members]

def require_team_management
  unless current_user.can_manage_team?
    redirect_to dashboard_path, alert: "You don't have permission to manage team members."
  end
end
```

### Invitation Workflow

**1. Owner/Admin Creates Invitation**
```ruby
invitation = current_account.invitations.create!(
  email: "newuser@example.com",
  role: "member",
  invited_by: current_user,
  expires_at: 7.days.from_now
)

# Send invitation email
InvitationMailer.invitation_email(invitation).deliver_later
```

**2. Email Sent with Token Link**
```
Subject: You've been invited to join FuegoMail

You've been invited to join ACCOUNT_NAME on FuegoMail.

Click here to accept: https://subdomain.fuegomail.com/invitations/TOKEN/accept

This invitation expires in 7 days.
```

**3. User Accepts Invitation (Public Page)**
```ruby
# No authentication required
def accept
  @invitation = Invitation.find_by_token!(params[:token])

  unless @invitation.valid_for_acceptance?
    redirect_to root_path, alert: "Invalid or expired invitation."
  end
end

def process_acceptance
  @invitation = Invitation.find_by_token!(params[:token])

  user = @invitation.accept!(
    first_name: params[:user][:first_name],
    last_name: params[:user][:last_name],
    password: params[:user][:password],
    password_confirmation: params[:user][:password_confirmation]
  )

  if user.persisted?
    sign_in(user)
    redirect_to dashboard_path, notice: "Welcome!"
  end
end
```

**4. User Created with Role**
```ruby
# In Invitation model
def accept!(user_params)
  User.create!(
    email: email,
    account: account,
    role: role,
    **user_params
  ).tap do |user|
    update!(accepted_at: Time.current)
  end
end
```

---

## AWS SES Integration

### Credential Storage

AWS credentials are stored encrypted using Active Record Encryption:

```ruby
# app/models/account.rb
encrypts :ses_access_key_id
encrypts :ses_secret_access_key
```

**Environment Variables Required:**
```bash
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=...
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=...
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=...
```

### SES Client Initialization

```ruby
# app/models/account.rb
def ses_client
  @ses_client ||= Aws::SESV2::Client.new(
    region: aws_region,
    credentials: Aws::Credentials.new(
      ses_access_key_id,
      ses_secret_access_key
    )
  )
end
```

### Sending Email

```ruby
# app/jobs/campaigns/send_email_job.rb
def perform(campaign_send_id)
  send_record = CampaignSend.find(campaign_send_id)
  account = send_record.campaign.account

  account.ses_client.send_email({
    from_email_address: send_record.campaign.from_email,
    destination: {
      to_addresses: [send_record.subscriber.email]
    },
    content: {
      simple: {
        subject: { data: send_record.campaign.subject },
        body: {
          html: { data: html_body },
          text: { data: text_body }
        }
      }
    },
    configuration_set_name: account.ses_configuration_set # Optional
  })
end
```

### Quota Monitoring

```ruby
# app/models/account.rb
def refresh_ses_quota!
  response = ses_client.get_account

  update!(
    ses_max_send_rate: response.send_quota.max_send_rate,
    ses_max_24_hour_send: response.send_quota.max_24_hour_send,
    ses_sent_last_24_hours: response.send_quota.sent_last_24_hours
  )
end
```

### SNS Webhook Processing

**Setup**: SNS topic subscribed to SES notifications (bounces, complaints, deliveries)

**Endpoint**: `POST /webhooks/sns`

**Implementation**:
```ruby
# app/controllers/webhooks_controller.rb
def sns
  message = JSON.parse(request.body.read)

  # Handle subscription confirmation
  if message["Type"] == "SubscriptionConfirmation"
    confirm_subscription(message)
    return head :ok
  end

  # Process notification
  notification = JSON.parse(message["Message"])

  case notification["notificationType"]
  when "Bounce"
    handle_bounce(notification)
  when "Complaint"
    handle_complaint(notification)
  when "Delivery"
    handle_delivery(notification)
  end

  head :ok
end

private

def handle_bounce(notification)
  email = notification["bounce"]["bouncedRecipients"].first["emailAddress"]
  bounce_type = notification["bounce"]["bounceType"] # "Permanent" or "Transient"

  subscriber = Subscriber.find_by(email: email)
  return unless subscriber

  if bounce_type == "Permanent"
    subscriber.update!(status: "bounced")
    subscriber.list_memberships.destroy_all # Unsubscribe from all lists
  end

  # Update campaign_send record
  campaign_send = find_campaign_send_from_message_id(notification)
  campaign_send&.mark_bounced!(bounce_type)
end

def handle_complaint(notification)
  email = notification["complaint"]["complainedRecipients"].first["emailAddress"]

  subscriber = Subscriber.find_by(email: email)
  return unless subscriber

  subscriber.update!(status: "complained")
  subscriber.list_memberships.destroy_all # Unsubscribe from all lists

  # Update campaign_send record
  campaign_send = find_campaign_send_from_message_id(notification)
  campaign_send&.mark_complained!
end
```

---

## Database Patterns

### SQLite Optimizations

FuegoMail uses SQLite in production with optimizations:

```ruby
# config/database.yml
production:
  adapter: sqlite3
  database: storage/production.sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000
  # Performance optimizations
  pragmas:
    journal_mode: :wal
    synchronous: :normal
    busy_timeout: 5000
    cache_size: -64000 # 64MB cache
    foreign_keys: true
    temp_store: :memory
```

**Why SQLite?**
- Production-ready for small-to-medium scale
- No separate database server needed
- Fast for read-heavy workloads
- Solid Queue uses same database
- Easy backups (single file)

### JSONB Pattern for Custom Attributes

Subscribers have flexible custom attributes:

```ruby
# app/models/subscriber.rb
store :custom_attributes, accessors: [], coder: JSON

# Usage
subscriber.custom_attributes = {
  "name" => "John Doe",
  "company" => "Acme Corp",
  "plan" => "Enterprise"
}

# In Mustache templates
Hello {{name}} from {{company}}!
```

### Counter Caching

Campaign stats use counter caching for performance:

```ruby
# app/models/campaign.rb
def sent_count
  campaign_sends.where(status: "sent").count
end

def opened_count
  campaign_sends.where.not(opened_at: nil).count
end

def clicked_count
  campaign_sends.where.not(clicked_at: nil).count
end
```

**Note**: These are NOT cached in database columns (yet). They're calculated on-demand. Consider adding counter cache columns if performance becomes an issue.

### Segment Count Caching

Segments cache their counts with refresh job:

```ruby
# app/models/segment.rb
def refresh_count!
  count = filter_subscribers(account.subscribers).count
  update!(
    cached_count: count,
    count_updated_at: Time.current
  )
end

def count_stale?
  count_updated_at.nil? || count_updated_at < 1.hour.ago
end

# Refreshed by background job
RefreshSegmentCountsJob.perform_later
```

---

## Testing Approach

### Test Structure

```
test/
├── models/          # Model unit tests
├── controllers/     # Controller integration tests
├── jobs/            # Background job tests
├── mailers/         # Mailer tests
└── integration/     # Full-stack integration tests
```

### Testing Patterns

**Model Tests:**
```ruby
# test/models/campaign_test.rb
class CampaignTest < ActiveSupport::TestCase
  test "should calculate bounce rate correctly" do
    campaign = campaigns(:newsletter)

    # Create sends
    10.times { campaign.campaign_sends.create!(subscriber: subscribers(:john), status: "delivered") }
    2.times { campaign.campaign_sends.create!(subscriber: subscribers(:jane), status: "bounced", bounce_type: "permanent") }

    assert_equal 16.67, campaign.bounce_rate
  end
end
```

**Job Tests:**
```ruby
# test/jobs/campaigns/send_email_job_test.rb
class Campaigns::SendEmailJobTest < ActiveJob::TestCase
  test "should send email via SES" do
    campaign_send = campaign_sends(:pending_send)

    assert_enqueued_with(job: Campaigns::SendEmailJob) do
      Campaigns::SendEmailJob.perform_later(campaign_send.id)
    end
  end
end
```

**Controller Tests:**
```ruby
# test/controllers/campaigns_controller_test.rb
class CampaignsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:demo)
    @user = users(:demo_user)
    sign_in @user
  end

  test "should create campaign" do
    assert_difference('Campaign.count') do
      post campaigns_url, params: {
        campaign: {
          name: "Test Campaign",
          list_id: lists(:newsletter).id,
          subject: "Test Subject",
          from_name: "Sender",
          from_email: "sender@example.com",
          body_markdown: "Test content"
        }
      }
    end

    assert_redirected_to campaign_url(Campaign.last)
  end
end
```

### Fixtures

Use fixtures for test data:

```yaml
# test/fixtures/accounts.yml
demo:
  subdomain: demo
  name: Demo Account
  aws_region: us-east-1
  plan: free
  active: true

# test/fixtures/users.yml
demo_user:
  account: demo
  email: demo@example.com
  first_name: Demo
  last_name: User
  role: owner

# test/fixtures/campaigns.yml
newsletter:
  account: demo
  list: newsletter
  name: Weekly Newsletter
  subject: This Week's Updates
  status: draft
```

---

## Common Development Tasks

### Adding a New Model

1. Generate migration and model
```bash
bin/rails generate model ModelName account:references field1:string field2:integer
```

2. Add account relationship
```ruby
# app/models/model_name.rb
class ModelName < ApplicationRecord
  belongs_to :account

  # Add account to Account model
  # app/models/account.rb
  has_many :model_names, dependent: :destroy
end
```

3. Add to controllers with account scoping
```ruby
# app/controllers/model_names_controller.rb
class ModelNamesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_model_name, only: [:show, :edit, :update, :destroy]

  def index
    @model_names = current_account.model_names
  end

  private

  def set_model_name
    @model_name = current_account.model_names.find(params[:id])
  end
end
```

### Adding a Background Job

1. Generate job
```bash
bin/rails generate job ProcessSomething
```

2. Implement perform method
```ruby
# app/jobs/process_something_job.rb
class ProcessSomethingJob < ApplicationJob
  queue_as :default

  def perform(record_id)
    record = SomeModel.find(record_id)
    # Process record
  end
end
```

3. Enqueue from model or controller
```ruby
ProcessSomethingJob.perform_later(record.id)
```

### Adding API Endpoint

1. Add route
```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :new_resource, only: [:index, :show, :create]
  end
end
```

2. Create controller
```ruby
# app/controllers/api/v1/new_resources_controller.rb
module Api
  module V1
    class NewResourcesController < Api::BaseController
      def index
        @resources = current_account.new_resources
        render json: @resources
      end

      def show
        @resource = current_account.new_resources.find(params[:id])
        render json: @resource
      end

      def create
        @resource = current_account.new_resources.create!(resource_params)
        render json: @resource, status: :created
      end

      private

      def resource_params
        params.require(:new_resource).permit(:field1, :field2)
      end
    end
  end
end
```

### Adding a Migration

1. Generate migration
```bash
bin/rails generate migration AddFieldToModel field:string
```

2. Edit migration if needed
```ruby
class AddFieldToModel < ActiveRecord::Migration[8.1]
  def change
    add_column :models, :field, :string
    add_index :models, :field # If needed
  end
end
```

3. Run migration
```bash
bin/rails db:migrate
```

### Adding a Stimulus Controller

1. Create controller file
```javascript
// app/javascript/controllers/example_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output"]
  static values = {
    url: String
  }

  connect() {
    console.log("Example controller connected")
  }

  doSomething() {
    // Action logic
  }
}
```

2. Use in view
```erb
<div data-controller="example" data-example-url-value="<%= some_path %>">
  <div data-example-target="output"></div>
  <button data-action="click->example#doSomething">Click Me</button>
</div>
```

---

## Code Patterns & Conventions

### Controller Patterns

**Standard CRUD:**
```ruby
class ResourcesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_resource, only: [:show, :edit, :update, :destroy]

  def index
    @resources = current_account.resources.order(created_at: :desc)
  end

  def show
  end

  def new
    @resource = current_account.resources.new
  end

  def create
    @resource = current_account.resources.new(resource_params)

    if @resource.save
      redirect_to @resource, notice: "Resource created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @resource.update(resource_params)
      redirect_to @resource, notice: "Resource updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @resource.destroy
    redirect_to resources_path, notice: "Resource deleted successfully."
  end

  private

  def set_resource
    @resource = current_account.resources.find(params[:id])
  end

  def resource_params
    params.require(:resource).permit(:field1, :field2)
  end
end
```

### Model Patterns

**Scopes:**
```ruby
class Campaign < ApplicationRecord
  scope :active, -> { where(status: ["sending", "approved"]) }
  scope :completed, -> { where(status: "completed") }
  scope :recent, -> { order(created_at: :desc).limit(10) }
end
```

**Callbacks:**
```ruby
class Subscriber < ApplicationRecord
  before_save :normalize_email
  after_create :send_welcome_email

  private

  def normalize_email
    self.email = email.downcase.strip
  end

  def send_welcome_email
    WelcomeMailer.welcome_email(self).deliver_later
  end
end
```

**State Management:**
```ruby
class Campaign < ApplicationRecord
  def send_now!
    # State transition logic
    update!(status: "sending", started_sending_at: Time.current)

    # Trigger workflow
    create_campaign_sends!
    approve_and_send!
  end

  def suspend_campaign!(reason)
    update!(
      status: "suspended",
      suspension_reason: reason,
      suspended_at: Time.current
    )

    # Notify user
    CampaignMailer.suspension_notification(self).deliver_later
  end
end
```

### View Patterns

**Partial Naming:**
```erb
<!-- app/views/campaigns/_campaign.html.erb -->
<div class="campaign-card">
  <%= campaign.name %>
</div>

<!-- Usage in index -->
<%= render @campaigns %>
```

**Form Patterns:**
```erb
<%= form_with(model: [@account, @campaign]) do |form| %>
  <% if @campaign.errors.any? %>
    <div class="alert alert-danger">
      <ul>
        <% @campaign.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div class="mb-3">
    <%= form.label :name, class: "form-label" %>
    <%= form.text_field :name, class: "form-control" %>
  </div>

  <%= form.submit class: "btn btn-primary" %>
<% end %>
```

**Turbo Frame Pattern:**
```erb
<!-- Show page -->
<%= turbo_frame_tag "campaign_stats" do %>
  <%= render "stats", campaign: @campaign %>
<% end %>

<!-- _stats.html.erb partial -->
<div class="stats">
  <div>Sent: <%= @campaign.sent_count %></div>
  <div>Opened: <%= @campaign.opened_count %></div>
</div>
```

### Styling Approach

**Centralized Bootstrap Theme**
- NO custom stylesheets on individual views
- Single central stylesheet: `app/assets/stylesheets/application.css`
- All views use only Bootstrap utility classes

**Example:**
```erb
<!-- GOOD: Uses Bootstrap utilities only -->
<div class="card border mb-3">
  <div class="card-body">
    <h5 class="mb-3">Title</h5>
  </div>
</div>

<!-- BAD: Inline styles or custom CSS -->
<style>
  .custom-card { ... }
</style>
<div class="custom-card">...</div>
```

### Naming Conventions

**Models:** Singular, PascalCase
- `Campaign`, `Subscriber`, `CampaignSend`

**Controllers:** Plural, PascalCase
- `CampaignsController`, `SubscribersController`

**Jobs:** Descriptive, PascalCase, ends with `Job`
- `SendEmailJob`, `ProcessQueuedCampaignJob`

**Routes:** Plural, snake_case
- `campaigns_path`, `subscribers_path`

**Database Tables:** Plural, snake_case
- `campaigns`, `subscribers`, `campaign_sends`

**Database Columns:** snake_case
- `first_name`, `created_at`, `aws_region`

---

## Gotchas & Important Considerations

### 1. Always Scope by Account

**Problem:** Global queries leak data between accounts
**Solution:** Always scope through `current_account`

```ruby
# BAD - Security issue!
Campaign.find(params[:id])

# GOOD - Scoped to account
current_account.campaigns.find(params[:id])
```

### 2. Percentage vs Static Thresholds

**Problem:** Static numbers don't scale with campaign size
**Solution:** Always use percentage-based calculations

```ruby
# BAD - 10 bounces might be normal for 10,000 sends
if bounced_count > 10
  suspend!
end

# GOOD - 8% bounce rate is significant at any scale
bounce_rate = (bounced_count.to_f / sent_count * 100).round(2)
if bounce_rate > 8.0
  suspend!
end
```

### 3. Minimum Sample Size for Rates

**Problem:** 1 bounce in 2 sends = 50% bounce rate (false positive)
**Solution:** Require minimum sample size before checking

```ruby
# Always check minimum sends first
return false if sent_count < 50

# Then calculate rates
bounce_rate = (bounced_count.to_f / sent_count * 100).round(2)
```

### 4. Async Operations Need Progress Tracking

**Problem:** Large operations with no feedback feel broken
**Solution:** Track progress in database, use auto-refresh UI

```ruby
# In job
total = items.count
items.each_with_index do |item, index|
  process(item)

  # Update progress every 100 items
  if (index + 1) % 100 == 0
    progress = ((index + 1).to_f / total * 100).round
    record.update_columns(progress: progress)
  end
end
```

### 5. SES Throttling is Critical

**Problem:** Exceeding SES send rate = throttle errors
**Solution:** Always respect account send rate limits

```ruby
# In enqueue job
campaign_sends.find_each do |send|
  Campaigns::SendEmailJob.perform_later(send.id)

  # Sleep to respect send rate (e.g., 14 emails/second = 0.071s between sends)
  sleep(1.0 / account.ses_max_send_rate)
end
```

### 6. Subdomain Required in Development

**Problem:** Some features don't work on `localhost`
**Solution:** Use subdomain in development

```bash
# Add to /etc/hosts
127.0.0.1 demo.localhost

# Access at
http://demo.localhost:3000
```

### 7. Encrypted Credentials Need Environment Variables

**Problem:** Production fails without encryption keys
**Solution:** Set environment variables before deployment

```bash
# Generate keys
bin/rails db:encryption:init

# Set in production environment
export ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=...
export ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=...
export ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=...
```

### 8. Campaign Status Transitions are One-Way

**Problem:** Invalid state transitions cause bugs
**Solution:** Only allow valid transitions

```ruby
# Valid transitions
draft → sending
sending → paused → sending (resumable)
sending → suspended (terminal, requires manual review)
sending → completed

# Invalid transitions (will break workflow)
completed → sending ❌
suspended → sending (without manual review) ❌
```

### 9. Bounce/Complaint Handling is Eventual

**Problem:** SNS webhooks are asynchronous
**Solution:** Don't expect immediate updates

- Campaign sends immediately
- Bounce/complaint arrives seconds/minutes later via SNS
- Stats update when webhook processed
- This is normal and expected behavior

### 10. Free Plan Limits are UI-Level Only

**Problem:** No database-level enforcement of plan limits
**Solution:** Limits are enforced in UI (disabled buttons, warnings)

**Current Implementation:**
- UI disables "New List" button when at limit
- UI shows warnings when limit reached
- No hard database constraint

**Future Enhancement:**
Consider adding database-level validation:
```ruby
# app/models/list.rb
validate :account_list_limit, on: :create

def account_list_limit
  if account.plan_free? && account.lists.count >= 1
    errors.add(:base, "Free plan limited to 1 list")
  end
end
```

### 11. Solid Queue Uses Same Database

**Problem:** Long-running jobs can lock database
**Solution:** Keep job units small and fast

- Break large operations into batches
- Use `find_each` instead of `all`
- Commit frequently (every 100 records)
- SQLite handles this well with WAL mode

### 12. Custom Attributes are Untyped

**Problem:** No schema validation for custom attributes
**Solution:** Always handle missing/invalid data gracefully

```ruby
# In Mustache templates
{{ name }} # May be nil or missing

# In code
subscriber.custom_attributes["name"] || "Valued Customer"
```

### 13. Turbo Compatibility

**Use Stimulus for JavaScript interactions:**
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Called when element appears (Turbo-safe)
    this.initialize()
  }

  disconnect() {
    // Called when element leaves (cleanup)
    this.cleanup()
  }
}
```

**Avoid inline JavaScript** unless handling both:
- `DOMContentLoaded` event
- `turbo:load` event

---

## Summary

Key takeaways for AI agents working on FuegoMail:

1. **Always scope by account** - Multi-tenancy is critical
2. **Use percentages, not static numbers** - For bounce/complaint thresholds
3. **Track progress for long operations** - With database fields and auto-refresh
4. **Respect SES rate limits** - Always throttle sending
5. **Understand campaign workflow** - Status transitions are one-way
6. **Risk management first** - Protect sender reputation above all
7. **SQLite is production-ready** - With proper configuration
8. **Solid Queue = no Redis** - Background jobs use database
9. **Encrypted credentials** - AWS keys use Active Record Encryption
10. **Hotwire for interactivity** - Turbo + Stimulus, minimal JavaScript

This codebase prioritizes:
- **Simplicity**: Minimal infrastructure (no Redis, no Postgres)
- **Safety**: Risk management at every level
- **Multi-tenancy**: Strict account isolation
- **User experience**: Progress indicators, real-time updates
- **Reliability**: Database-backed jobs, encrypted credentials

When in doubt, refer to existing patterns in the codebase. The conventions are consistent throughout.
