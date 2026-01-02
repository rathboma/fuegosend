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

1. Fix all 🔴 Critical Bugs first (will prevent runtime errors)
2. Complete 🟠 High Priority items (needed for production)
3. Add 🟡 Medium Priority features (better user experience)
4. Consider 🟢 Low Priority when core is stable

---

Last Updated: 2026-01-02
Status: ~70% feature complete
