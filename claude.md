# FuegoMail Development Notes

This document captures key architectural decisions, patterns, and learnings from the FuegoMail project.

## Project Overview

FuegoMail is a self-hosted email marketing SaaS application built with Rails 8.1.1, designed as a Sendy alternative.

## Key Technologies

- **Rails 8.1.1** - Main framework
- **SQLite** with JSON support - Database
- **Bootstrap 5.3.2** (CDN) - UI framework
- **Turbo** - SPA-like navigation
- **AWS SES** - Email sending
- **Mustache** - Email templating
- **CodeMirror v5** - Markdown editor
- **Kramdown** - Markdown to HTML conversion

## Styling Approach

### Centralized Bootstrap Theme
- **NO custom stylesheets on individual views**
- Single central stylesheet: `app/assets/stylesheets/application.css`
- Contains app-wide Bootstrap variable overrides and customizations
- All views use only Bootstrap utility classes

### Rationale
- Consistent design across entire application
- Easier maintenance - one place to change styling
- Smaller view files, better separation of concerns
- Faster development - no style duplication

### Color Scheme
- Primary: `#4CAF50` (green)
- Grey background for email previews: `#f4f4f4`
- Status badges use semantic Bootstrap colors

### Example Pattern
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

## Multi-Step Form Pattern

### Campaign Creation Workflow
Implemented a 3-step wizard for campaign creation:
1. **Details** - Name, subject, sender info, list selection
2. **Content** - Markdown editor with live preview
3. **Review** - Summary and final send options

### Key Implementation Details

**Progress Indicator**
- Visual progress bar showing 33%, 66%, 100%
- Clickable step labels for navigation (when campaign is persisted)
- Current step highlighted in primary color
- Disabled steps for new campaigns until saved

**Dynamic Container Width**
- Step 1: 900px (narrow for forms)
- Step 2 & 3: 1400px (wide for side-by-side layouts)

**Step Parameter Handling**
```ruby
# Use params.dig for safe nested access (avoids nil errors)
@step = params.dig(:campaign, :step)&.to_i || params[:step]&.to_i || 1
```

**Navigation Flow**
- Step 1 save → redirects to Step 2
- Step 2 save → redirects to Step 3
- Step links allow jumping between steps (edit mode only)

## Email Templating with Mustache

### Why Mustache?
- Logic-less templates (security)
- Simple syntax familiar to users
- Native Ruby library available

### Variable Syntax

**Single Braces (Escaped HTML)**
```mustache
{{email}}              → subscriber@example.com
{{name}}               → John Doe
{{campaign_name}}      → Newsletter Jan 2025
{{account_name}}       → Your Company
{{current_year}}       → 2025
```

**Triple Braces (Raw HTML)**
```mustache
{{{content}}}          → Renders markdown as HTML (not escaped)
```

### Custom Attributes Pattern
Custom attributes are flattened for easier access:
- `subscriber.custom_attributes = {first_name: "John", company: "Acme"}`
- Becomes: `{{custom_first_name}}`, `{{custom_company}}`

### Template Data Structure
```ruby
{
  # Content
  content: campaign_content_html,

  # Subscriber
  email: subscriber.email,
  name: subscriber.get_attribute("name"),

  # Custom attributes (flattened)
  custom_first_name: subscriber.get_attribute("first_name"),
  custom_company: subscriber.get_attribute("company"),
  # ... any other custom_attributes keys

  # Campaign
  campaign_name: campaign.name,
  campaign_subject: campaign.subject,

  # Account
  account_name: account.name,
  logo_url: account.brand_logo.presence || "/logo-placeholder.png",

  # URLs
  unsubscribe_url: "#unsubscribe",

  # Helpers
  current_year: Time.current.year
}
```

## Turbo Compatibility

### JavaScript Initialization Pattern
Must handle both page load and Turbo navigation:

```javascript
(function() {
  function initializeComponent() {
    // Check if already initialized
    if (document.querySelector('.already-initialized')) {
      return;
    }

    // Your initialization code
  }

  // Listen to both events
  document.addEventListener('DOMContentLoaded', initializeComponent);
  document.addEventListener('turbo:load', initializeComponent);

  // Also try immediate initialization
  if (document.readyState !== 'loading') {
    initializeComponent();
  }
})();
```

### Why This Pattern?
- `DOMContentLoaded` - Fires on full page loads
- `turbo:load` - Fires on Turbo navigation
- Immediate check - Handles cases where script loads after DOM ready
- IIFE wrapper - Avoids global namespace pollution
- Idempotency check - Prevents double initialization

## CodeMirror Integration

### Setup
```html
<!-- CSS -->
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/codemirror.min.css">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/theme/monokai.min.css">

<!-- JS -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/codemirror.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/mode/markdown/markdown.min.js"></script>
```

### Configuration
```javascript
const editor = CodeMirror.fromTextArea(textarea, {
  mode: 'markdown',
  theme: 'monokai',
  lineNumbers: true,
  lineWrapping: true,
  viewportMargin: Infinity,
  height: '600px'
});
```

### Syncing with Hidden Field
```javascript
// Update hidden field on change
editor.on('change', function() {
  hiddenField.value = editor.getValue();
});

// Ensure sync before form submit
form.addEventListener('submit', function() {
  hiddenField.value = editor.getValue();
});
```

## Live Preview Implementation

### Markdown Rendering
- Client-side: `marked.js` for instant preview
- Server-side: `kramdown` gem for final rendering

### Template Merging
```javascript
// Convert markdown to HTML
const html = marked.parse(markdown);

// Merge into template
finalHtml = templateHtml
  .replace(/\{\{\{content\}\}\}/g, html)
  .replace(/\{\{logo_url\}\}/g, logoUrl);
```

### Preview Styling
- Grey background matches email wrapper
- Full template styling visible
- Responsive preview container

## Database Patterns

### Reserved Word Avoidance
**Problem:** `attributes` is a reserved ActiveRecord method

**Solution:** Renamed to `custom_attributes`
```ruby
# Migration
rename_column :subscribers, :attributes, :custom_attributes

# Model
def get_attribute(key)
  custom_attributes&.dig(key)
end
```

### JSON Column Usage
SQLite supports JSON columns for flexible data storage:
```ruby
# Schema
create_table :subscribers do |t|
  t.json :custom_attributes, default: {}
end

# Queries
Subscriber.where("json_extract(custom_attributes, '$.company') = ?", "Acme")
```

## Asset Management

### Public vs Assets

**Use `public/` for:**
- Images referenced in emails (need full URL)
- Static files accessed by external systems
- Default images (logo-placeholder.png)

**Use `app/assets/` for:**
- Stylesheets
- Application JavaScript
- Images only used in views

### CDN Strategy
External libraries loaded via CDN:
- Bootstrap (CSS/JS)
- CodeMirror
- Marked.js

**Benefits:**
- Faster initial load from CDN caching
- No asset compilation needed
- Easy version management

## Parameter Safety

### Using `dig` for Nested Parameters
```ruby
# UNSAFE - raises error if params[:campaign] is nil
@step = params[:campaign][:step]&.to_i

# SAFE - returns nil if any key is missing
@step = params.dig(:campaign, :step)&.to_i || 1
```

### When Forms Have Different Structures
Different forms submit different parameter structures:
- Campaign edit form: `params[:campaign][:step]`
- Test email form: `params[:test_email]` (no campaign nesting)
- URL parameters: `params[:step]`

Solution: Check multiple sources with fallbacks
```ruby
@step = params.dig(:campaign, :step)&.to_i || params[:step]&.to_i || 1
```

## Model Concerns

### Keeping Models Clean
Separate concerns into dedicated methods:

```ruby
class Template < ApplicationRecord
  # Public API
  def render_for(subscriber, campaign)
    template_content = rendered_html
    data = build_mustache_data(subscriber, campaign)
    Mustache.render(template_content, data)
  end

  private

  # Data preparation
  def build_mustache_data(subscriber, campaign)
    # Build data hash
  end

  # Attribute flattening
  def flatten_custom_attributes(subscriber)
    # Transform custom_attributes hash
  end
end
```

## Common Pitfalls & Solutions

### 1. HTML Escaping in Mustache
**Problem:** Content renders as escaped HTML
```
&lt;h1&gt;Title&lt;/h1&gt;
```

**Solution:** Use triple braces for HTML content
```mustache
{{{content}}}  <!-- Raw HTML -->
{{email}}      <!-- Escaped text -->
```

### 2. Turbo JavaScript Issues
**Problem:** JavaScript only works on full page refresh

**Solution:** Listen to both `DOMContentLoaded` and `turbo:load`

### 3. Form Parameter Access Errors
**Problem:** `NoMethodError: undefined method '[]' for nil`

**Solution:** Use `params.dig(:key, :nested)` instead of `params[:key][:nested]`

### 4. Custom Attributes Naming Conflict
**Problem:** `attributes` conflicts with ActiveRecord

**Solution:** Use `custom_attributes` and provide helper methods

## File Organization

```
app/
├── assets/
│   ├── stylesheets/
│   │   └── application.css      # Centralized Bootstrap customizations
│   └── images/
│       └── logo-placeholder.png  # Copied to public/
├── controllers/
│   └── campaigns_controller.rb   # Multi-step form handling
├── jobs/
│   └── campaigns/
│       ├── send_email_job.rb         # Sends individual campaign emails
│       ├── send_test_email_job.rb    # Sends test emails
│       ├── enqueue_sending_job.rb    # Batch enqueues campaign sends
│       └── send_scheduled_job.rb     # Triggers scheduled campaigns
├── models/
│   ├── campaign.rb               # Mustache data building
│   └── template.rb               # Template rendering
├── services/
│   └── ses/
│       ├── email_sender.rb           # Campaign email sending
│       └── test_email_sender.rb      # Test email sending
└── views/
    └── campaigns/
        ├── _form.html.erb        # Progress stepper
        ├── _step1.html.erb       # Campaign details
        ├── _step2.html.erb       # Content editor + preview
        └── _step3.html.erb       # Review + send

public/
└── logo-placeholder.png          # Default logo for emails
```

## Testing Considerations

### Email Preview Without Sending
All preview functionality works without AWS SES configured:
- Step 2: Live markdown preview
- Step 3: Full email preview with template
- Uses sample subscriber data

### Test Email Feature
Test emails use the same infrastructure as real campaign emails for consistency:

**Architecture:**
- `Ses::TestEmailSender` - Service class for sending test emails
- `Campaigns::SendTestEmailJob` - Background job that enqueues test sends
- Reuses campaign rendering and SES client from main sending flow

**Key Differences from Campaign Emails:**
```ruby
# Test emails:
# - Prefix subject with "[TEST]"
# - Add visual test notice at top of email
# - Skip tracking pixels and link tracking
# - Skip rate limiting (send immediately)
# - Don't create CampaignSend records
# - Use sample/first subscriber data for merge tags

# Real campaign emails:
# - Full subject line
# - Include tracking pixels and link tracking
# - Rate limited based on SES quotas
# - Create CampaignSend records for each recipient
# - Use actual subscriber data
```

**Sample Subscriber Logic:**
```ruby
def build_sample_subscriber
  # Try first subscriber from campaign's list
  first_subscriber = campaign.list.subscribers.first

  return first_subscriber if first_subscriber

  # Fallback: Create mock subscriber (not persisted)
  Subscriber.new(
    email: recipient_email,
    custom_attributes: {
      'name' => 'Test User',
      'first_name' => 'Test',
      'last_name' => 'User'
    }
  )
end
```

**Usage Flow:**
1. User enters email in Step 3 review screen
2. Controller validates email and campaign readiness
3. `Campaigns::SendTestEmailJob.perform_later(campaign_id, email)`
4. Job instantiates `Ses::TestEmailSender` and sends
5. User receives test email with "[TEST]" prefix

## Performance Notes

### Preview Optimization
- Client-side markdown rendering (instant feedback)
- No server round-trips for preview updates
- Template loaded once on page load

### Database Queries
- Eager loading associations in controllers
- JSON column queries for custom attributes
- Cached subscriber counts on lists

## Security Considerations

### Template Safety
- Mustache is logic-less (no Ruby code execution)
- All HTML is sanitized with Rails `sanitize` helper
- User-provided markdown rendered server-side with kramdown

### Email Content
- No direct database queries in templates
- All merge tags pre-defined and whitelisted
- XSS protection via proper escaping

## Future Improvements

### Template System
- [ ] Visual template builder
- [ ] Template preview with sample data
- [ ] Conditional sections support

### Campaign Features
- [ ] A/B testing
- [ ] Send time optimization
- [ ] Advanced scheduling

### Editor Enhancements
- [ ] Image upload support
- [ ] Template snippets
- [ ] Markdown toolbar

## Useful Commands

```bash
# Reset and seed database
bin/rails db:drop db:create db:migrate db:seed

# Rails console
bin/rails console

# Run specific migration
bin/rails db:migrate:up VERSION=20251223170906

# View routes
bin/rails routes | grep campaigns
```

## Related Documentation

- [Rails Guides](https://guides.rubyonrails.org/)
- [Bootstrap 5 Docs](https://getbootstrap.com/docs/5.3/)
- [Mustache Manual](https://mustache.github.io/mustache.5.html)
- [CodeMirror v5 Docs](https://codemirror.net/5/doc/manual.html)
- [Kramdown Syntax](https://kramdown.gettalong.org/syntax.html)
