import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "hiddenField", "preview"]
  static values = {
    previewUrl: String
  }

  connect() {
    this.debounceTimer = null
    this.waitForCodeMirror().then(() => {
      this.initializeEditor()
    })
  }

  disconnect() {
    if (this.editor) {
      this.editor.toTextArea()
      this.editor = null
    }
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
  }

  waitForCodeMirror() {
    return new Promise((resolve) => {
      if (typeof CodeMirror !== 'undefined') {
        resolve()
      } else {
        // Poll for CodeMirror to be loaded
        const checkInterval = setInterval(() => {
          if (typeof CodeMirror !== 'undefined') {
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

    // Update preview on change with debouncing
    this.editor.on('change', () => {
      this.debouncedUpdatePreview()
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

  debouncedUpdatePreview() {
    // Clear existing timer
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    // Sync to hidden field immediately
    this.syncToHiddenField()

    // Set new timer to update preview after 500ms of no typing
    this.debounceTimer = setTimeout(() => {
      this.updatePreview()
    }, 500)
  }

  async updatePreview() {
    const markdown = this.editor.getValue()

    try {
      // Build URL with content as query parameter
      const url = new URL(this.previewUrlValue, window.location.origin)
      url.searchParams.set('content', markdown)

      // Fetch preview
      const response = await fetch(url)

      // Get the HTML response (includes errors in development mode)
      const html = await response.text()

      // Update iframe content (will show error trace in dev or preview in prod)
      const iframe = this.previewTarget
      const iframeDoc = iframe.contentDocument || iframe.contentWindow.document
      iframeDoc.open()
      iframeDoc.write(html)
      iframeDoc.close()
    } catch (error) {
      console.error('Failed to fetch preview:', error)
      // Show network error in iframe
      const iframe = this.previewTarget
      const iframeDoc = iframe.contentDocument || iframe.contentWindow.document
      iframeDoc.open()
      iframeDoc.write(`
        <div style="padding: 20px; background: #f8d7da; color: #721c24; font-family: monospace;">
          <h3>Network Error</h3>
          <p>Failed to fetch preview from server.</p>
          <pre>${error.message}</pre>
        </div>
      `)
      iframeDoc.close()
    }
  }
}
