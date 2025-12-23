import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "hiddenField", "preview"]
  static values = {
    template: String,
    logoUrl: String,
    accountName: String,
    campaignName: String,
    campaignSubject: String
  }

  connect() {
    // Wait for CodeMirror to be loaded
    this.waitForCodeMirror().then(() => {
      this.initializeEditor()
    })
  }

  disconnect() {
    if (this.editor) {
      this.editor.toTextArea()
      this.editor = null
    }
  }

  waitForCodeMirror() {
    return new Promise((resolve) => {
      if (typeof CodeMirror !== 'undefined' && typeof marked !== 'undefined') {
        resolve()
      } else {
        // Poll for CodeMirror and marked to be loaded
        const checkInterval = setInterval(() => {
          if (typeof CodeMirror !== 'undefined' && typeof marked !== 'undefined') {
            clearInterval(checkInterval)
            resolve()
          }
        }, 100)
      }
    })
  }

  initializeEditor() {
    if (this.editor) {
      return // Already initialized
    }

    if (!this.hasTextareaTarget || !this.hasHiddenFieldTarget || !this.hasPreviewTarget) {
      console.error('Required targets not found')
      return
    }

    // Initialize CodeMirror
    this.editor = CodeMirror.fromTextArea(this.textareaTarget, {
      mode: 'markdown',
      theme: 'monokai',
      lineNumbers: true,
      lineWrapping: true,
      viewportMargin: Infinity
    })

    this.editor.setSize(null, '600px')

    // Update preview on change
    this.editor.on('change', () => {
      this.updatePreview()
    })

    // Initial preview
    this.updatePreview()

    // Update hidden field before form submit
    const form = this.element.closest('form')
    if (form) {
      form.addEventListener('submit', () => {
        this.syncToHiddenField()
      })
    }
  }

  syncToHiddenField() {
    if (this.editor) {
      this.hiddenFieldTarget.value = this.editor.getValue()
    }
  }

  updatePreview() {
    const markdown = this.editor.getValue()

    // Convert markdown to HTML
    const html = marked.parse(markdown)

    // Sync with hidden field
    this.syncToHiddenField()

    // Apply template if available
    let finalHtml = html
    if (this.hasTemplateValue && this.templateValue) {
      // Replace content placeholders in template
      finalHtml = this.templateValue
        .replace(/\{\{\{content\}\}\}/g, html)
        .replace(/\{\{\{body\}\}\}/g, html)
        .replace(/\{\{\{email_content\}\}\}/g, html)
        .replace(/\{\{content\}\}/g, html)
        .replace(/\{\{body\}\}/g, html)
        .replace(/\{\{email_content\}\}/g, html)
    } else {
      // No template, wrap in simple container
      finalHtml = '<div style="max-width: 600px; margin: 0 auto; padding: 20px;">' + html + '</div>'
    }

    // Get values with fallbacks
    const logoUrl = this.hasLogoUrlValue ? this.logoUrlValue : '/logo-placeholder.png'
    const accountName = this.hasAccountNameValue ? this.accountNameValue : 'Your Company'
    const campaignName = this.hasCampaignNameValue ? this.campaignNameValue : 'Campaign Name'
    const campaignSubject = this.hasCampaignSubjectValue ? this.campaignSubjectValue : 'Email Subject'

    // Replace example merge tags for preview
    finalHtml = finalHtml
      .replace(/\{\{email\}\}/g, 'subscriber@example.com')
      .replace(/\{\{custom_(\w+)\}\}/g, 'John Doe')
      .replace(/\{\{name\}\}/g, 'John Doe')
      .replace(/\{\{first_name\}\}/g, 'John')
      .replace(/\{\{last_name\}\}/g, 'Doe')
      .replace(/\{\{unsubscribe_url\}\}/g, '#unsubscribe')
      .replace(/\{\{campaign_name\}\}/g, campaignName)
      .replace(/\{\{campaign_subject\}\}/g, campaignSubject)
      .replace(/\{\{account_name\}\}/g, accountName)
      .replace(/\{\{logo_url\}\}/g, logoUrl)
      .replace(/\{\{current_year\}\}/g, new Date().getFullYear())

    this.previewTarget.innerHTML = finalHtml
  }
}
