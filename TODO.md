# FuegoMail Development TODO

This is a prioritized list of features, fixes, and improvements for FuegoMail.

## 🔴 Critical Bugs (Fix Immediately)

These will cause runtime errors in production:

- [ ] **Add `Account#paused?` method** (app/models/account.rb)
  - Method is called in `can_send_email?` but not defined
  - Schema has `paused_at` column - needs scope/method to check it
  - Location: Used in line 62 of account.rb

- [ ] **Implement `Campaign#apply_merge_tags` method** (app/models/campaign.rb)
  - Called in `Ses::EmailSender.prepare_text_body` (line 101)
  - Will cause NoMethodError when preparing plain text emails
  - Should apply Mustache rendering to text content

- [ ] **Fix unsubscribe URL generation** (app/models/campaign.rb, app/models/template.rb)
  - Currently returns placeholder `"#unsubscribe"` in mustache data
  - Real URL generation logic exists but not integrated
  - Unsubscribe flow won't work without this

- [ ] **Implement API authentication** (app/controllers/api/v1/base_controller.rb)
  - `ApiAuthenticable` module referenced but doesn't exist
  - All API endpoints will fail without this
  - Need bearer token validation from ApiKey model

- [ ] **Create notification mailer methods** (app/mailers/)
  - Campaign model has 4 stub methods (lines 252-267):
    - `notify_sending_started!`
    - `notify_sending_completed!`
    - `notify_sending_failed!`
    - `notify_quota_exceeded!`
  - All marked "will implement with mailer" but are empty

## 🔥 Automated Risk Management System (High Priority)

**Goal:** Implement self-managed anti-abuse system that isolates risk and automates spam detection without manual oversight. See `risk-management-todo.md` for full requirements.

### Domain Segmentation (Reputation Isolation)

- [ ] **Add `plan` field to Account model**
  - Migration: Add enum field with values: `free`, `starter`, `pro`, `agency`
  - Add plan-based feature gating methods
  - Set default plan for new accounts

- [ ] **Add tracking domain configuration to accounts**
  - Migration: Add `tracking_domain` field to accounts
  - Create domain tier assignment logic:
    - Tier 1 (Disposable): Pool of domains for Free plan (e.g., `links-cluster-a.com`)
    - Tier 2 (Premium): Single domain for Paid plans (e.g., `track.fuegomail.com`)
    - Tier 3 (Custom): CNAME support for Agency plan (e.g., `links.brand.com`)
  - Update URL generation in tracking controller and email sender

- [ ] **Configure web server for multi-domain tracking**
  - Update Nginx/web server config to accept all tracking domains
  - Add domain routing logic in Rails
  - Test click/open tracking across all domain tiers

### Campaign State Machine for Risk Management

- [ ] **Extend Campaign status enum with new states**
  - Add states: `queued_for_review`, `canary_processing`, `approved`, `suspended`
  - Update campaign state machine transitions
  - Add migration to update existing campaigns

- [ ] **Implement Sandbox workflow (Free Plan only)**
  - Phase A: 30-minute cool-down delay after "Send" clicked
    - Add `queued_at` timestamp to campaigns
    - Create background job to check timer and advance state
  - Phase B: Canary sample (for lists > 500)
    - Select random 100 contacts for canary batch
    - Send only canary batch, transition to `canary_processing`
    - Start 30-minute analysis timer
  - Phase C: Analysis & decision logic
    - Check bounce/complaint rates from SES webhooks for canary batch
    - Thresholds: >5% hard bounces OR >1% complaints = FAIL
    - FAIL: Set status to `suspended`, trigger alert
    - PASS: Set status to `approved`, send remaining emails
  - Add `canary_send_ids` JSON field to track canary batch

- [ ] **Implement Emergency Kill-Switch (All Plans)**
  - Real-time monitoring during send
  - Check cumulative stats: >10 hard bounces OR >2 complaints
  - Immediately stop campaign and set to `suspended`
  - Applies to all users (Free & Paid) during entire send process

- [ ] **Add plan-based workflow routing**
  - Free plan: Goes through Sandbox & Canary workflow
  - Paid plans: Bypass sandbox, go straight to `approved`/sending
  - Add specs/tests for both paths

### Free Plan User Constraints

- [ ] **Limit Free users to 1 list/segment**
  - Add validation in List and Segment models
  - Check account plan before allowing creation
  - Show upgrade prompt in UI when limit reached

- [ ] **Add import throttling for Free plan**
  - Add `pending_validation` state to subscribers
  - New imports stay in `pending_validation` for 30 minutes
  - Background job transitions to `active` after timer
  - Prevent campaigns from using `pending_validation` subscribers

- [ ] **Add UI indicators for Free plan restrictions**
  - Show "1/1 lists used" counter
  - Show validation timer on imported contacts
  - Add upgrade prompts in appropriate places

### Risk Management UI & Messaging

- [ ] **Update campaign status UI with new states**
  - `queued_for_review`: Display "Status: Queued for Delivery"
  - `canary_processing`: Display "Status: Sending & Verifying"
  - `suspended`: Display suspension reason and recovery steps
  - Add tooltips with positive messaging (avoid "delayed", "hold", "probation")

- [ ] **Create suspended campaign recovery flow**
  - Show bounce/complaint statistics that triggered suspension
  - Recommend list cleaning tools
  - Allow manual resume after review (admin only initially)
  - Log suspension events for audit

- [ ] **Add knowledge base content**
  - Article: "Why is my campaign status 'Queued'?" (Smart Queuing Algorithm)
  - Article: "How tracking links affect delivery" (domain tiers)
  - Article: "Why was my campaign paused?" (bounce rate protection)
  - FAQ: Upgrade to bypass delays, explain Free plan process

### Risk Management Background Jobs

- [ ] **Create `RiskManagement::ProcessQueuedCampaignJob`**
  - Runs every minute to check `queued_for_review` campaigns
  - Advances campaigns past 30-minute cooldown to canary phase
  - Free plan only

- [ ] **Create `RiskManagement::AnalyzeCanaryCampaignJob`**
  - Runs every minute to check `canary_processing` campaigns
  - Analyzes bounce/complaint rates after 30-minute analysis timer
  - Makes PASS/FAIL decision and advances state

- [ ] **Create `RiskManagement::MonitorActiveCampaignsJob`**
  - Runs every 30 seconds
  - Checks all `sending` campaigns for kill-switch thresholds
  - Suspends campaigns that exceed bounce/complaint limits
  - Applies to all plans

- [ ] **Create `RiskManagement::ActivatePendingSubscribersJob`**
  - Runs every 5 minutes
  - Transitions subscribers from `pending_validation` to `active`
  - Only for Free plan imports

### Dependencies & Notes

- Requires: `Account#paused?` method fixed (Critical Bug)
- Requires: Bounce/complaint webhook tracking working correctly
- Requires: Campaign statistics accurate and real-time
- Consider: Add admin dashboard to view suspended campaigns across all accounts
- Consider: Add alerts/notifications when campaigns are suspended

## 🟠 High Priority (Complete Core Features)

Features needed for basic production use:

- [ ] **Add `ses_configuration_set_name` field to accounts**
  - Create migration for the field
  - EmailSender checks for it (line 53) but field doesn't exist
  - Needed for advanced SES tracking (opens/clicks)

- [ ] **Create subscription confirmation email template**
  - View: `app/views/subscription_mailer/confirm_subscription.html.erb`
  - Mailer action exists but template missing
  - Required for double opt-in flow

- [ ] **Implement bounce/complaint suppression list**
  - Bounces/complaints are tracked but not prevented
  - Add validation to prevent sending to bounced/complained subscribers
  - Create UI to view/manage suppression list

- [ ] **Add segment count refresh background job**
  - Segments have `count_stale?` logic (1 hour TTL)
  - No background job to refresh stale counts
  - Users see outdated counts with no indication

- [ ] **Fix campaign pause reason handling**
  - Pause reasons aren't consistent across error handling
  - Add UI to show pause reason and recovery steps
  - Different pause reasons should have different resume logic

- [ ] **Improve test email error handling**
  - Doesn't handle missing content gracefully
  - Error redirects to step 3 when user might be on step 2
  - Add better validation and user feedback

- [ ] **Add progress indication for large campaigns**
  - Campaign#create_campaign_sends has no progress indication
  - For 10k+ subscribers, UI shows nothing during creation
  - Add progress bar or async creation with status updates

## 🟡 Medium Priority (Enhanced Functionality)

Features that improve usability:

- [ ] **Multi-user team support**
  - User invitation system
  - Team role management (owner/admin/member)
  - Permission-based access control

- [ ] **API rate limiting**
  - Per-account API rate limits
  - Request throttling on public endpoints
  - Rate limit headers in responses

- [ ] **Enhanced analytics dashboard**
  - Trend graphs for campaigns
  - Engagement scoring for subscribers
  - Click heatmaps for email content
  - Comparative campaign analytics

- [ ] **Batch operations**
  - Bulk subscriber operations (tag, unsubscribe, delete)
  - Bulk campaign operations (pause, resume, delete)
  - Segment member export (CSV)

- [ ] **Email template improvements**
  - Pre-built responsive templates
  - Template categories/tags
  - Template preview without campaign
  - Template versioning

- [ ] **Subscription form validation**
  - Validate custom field definitions exist
  - Better error messages
  - CAPTCHA/bot protection
  - Custom success/error pages

- [ ] **Campaign scheduling improvements**
  - Time zone support for scheduling
  - Recurring campaigns (daily, weekly, monthly)
  - Send time optimization based on subscriber timezone

## 🟢 Low Priority (Nice to Have)

Features for advanced use cases:

- [ ] **Visual email template builder**
  - Drag-and-drop interface
  - Block-based editing
  - Preview across email clients
  - Save blocks for reuse

- [ ] **Automation workflows**
  - Drip campaigns
  - Triggered emails (welcome, birthday, abandoned cart)
  - Workflow builder UI
  - Conditional logic

- [ ] **A/B testing**
  - Subject line testing
  - Content testing
  - Send time testing
  - Automatic winner selection

- [ ] **Advanced segmentation**
  - Behavioral segmentation (engagement, opens, clicks)
  - Purchase history integration
  - Dynamic segments with real-time updates
  - Segment combinations (AND/OR logic)

- [ ] **Enhanced tracking**
  - Browser/device detection (use proper gem like `browser`)
  - Geographic tracking
  - Time-to-open metrics
  - Forwarding detection

- [ ] **Reputation monitoring**
  - CloudWatch integration for reputation metrics
  - Automated alerts for bounce/complaint spikes
  - Sender score tracking
  - Deliverability reports

- [ ] **Integration framework**
  - Webhook system for external integrations
  - Zapier integration
  - Third-party app marketplace
  - Custom integration API

- [ ] **White-label support**
  - Custom domain for each account
  - Branding customization
  - Email branding removal option
  - Custom SMTP relay support

## 📝 Code Quality & Performance

Technical debt and optimizations:

- [ ] **Add comprehensive test coverage**
  - Model validations
  - Controller actions
  - Background jobs
  - Service objects
  - API endpoints

- [ ] **Performance optimizations**
  - Add database query optimization
  - Add caching for frequently accessed data
  - Optimize N+1 queries
  - Add pagination to all list views

- [ ] **Error monitoring integration**
  - Add Sentry or similar error tracking
  - Track SES API errors
  - Monitor background job failures
  - Alert on critical errors

- [ ] **Documentation**
  - API documentation (OpenAPI/Swagger)
  - Setup guide for developers
  - Deployment guide
  - Architecture documentation

- [ ] **Security improvements**
  - Add CSRF protection verification
  - Add rate limiting to authentication
  - Add two-factor authentication
  - Security audit of file uploads

## 🎯 Current Focus

Based on priorities, the recommended order of work is:

1. **Fix all 🔴 Critical Bugs first** (will prevent runtime errors)
   - These are blockers that will cause immediate failures

2. **Implement 🔥 Automated Risk Management System** (production requirement)
   - Essential for preventing abuse and protecting sender reputation
   - Enables Free plan with appropriate safeguards
   - Should be done before scaling to multiple users

3. **Complete 🟠 High Priority items** (needed for production)
   - Foundation features like API auth, notifications, suppression lists

4. **Add 🟡 Medium Priority features** (better user experience)
   - Multi-user teams, analytics, batch operations

5. **Consider 🟢 Low Priority** when core is stable
   - Advanced features for mature product

### Implementation Strategy for Risk Management

The risk management system should be implemented in this order:

1. **Phase 1: Foundation**
   - Add `plan` field to accounts
   - Extend campaign status enum
   - Add required timestamps and tracking fields

2. **Phase 2: Domain Segmentation**
   - Configure tracking domain tiers
   - Update URL generation logic
   - Test multi-domain tracking

3. **Phase 3: Sandbox Workflow**
   - Implement 30-minute cooldown
   - Implement canary sampling logic
   - Build analysis & decision engine
   - Add background jobs for automation

4. **Phase 4: Kill-Switch**
   - Real-time monitoring job
   - Emergency suspension logic
   - Alert system

5. **Phase 5: Free Plan Constraints**
   - List/segment limits
   - Import throttling
   - UI updates and upgrade prompts

6. **Phase 6: Documentation**
   - Update UI messaging
   - Create knowledge base articles
   - Add FAQ content

---

Last Updated: 2026-01-02
Status: ~60% feature complete (updated to reflect new risk management scope)
Dependencies: See `risk-management-todo.md` for detailed requirements
