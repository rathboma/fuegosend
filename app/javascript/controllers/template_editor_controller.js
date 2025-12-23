import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "hiddenField", "preview", "saveStatus", "imageUpload", "imageModal", "imageUrl"]
  static values = {
    previewUrl: String,
    saveUrl: String,
    csrfToken: String,
    uploadUrl: String
  }

  connect() {
    this.debounceTimer = null
    this.maxWaitTimer = null
    this.lastUpdateTime = Date.now()
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
    if (this.maxWaitTimer) {
      clearTimeout(this.maxWaitTimer)
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

    // Initialize CodeMirror with HTML mode
    this.editor = CodeMirror.fromTextArea(this.textareaTarget, {
      mode: 'htmlmixed',
      theme: 'monokai',
      lineNumbers: true,
      lineWrapping: true,
      viewportMargin: Infinity,
      autoCloseTags: true,
      matchTags: true
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
    const DEBOUNCE_DELAY = 500  // Wait 500ms after typing stops
    const MAX_WAIT = 2000        // Force update after 2s of continuous typing

    // Sync to hidden field immediately
    this.syncToHiddenField()

    // Check if we've been waiting too long since last update
    const timeSinceLastUpdate = Date.now() - this.lastUpdateTime
    if (timeSinceLastUpdate >= MAX_WAIT) {
      // Force update now
      this.clearTimers()
      this.updatePreviewAndResetTimers()
      return
    }

    // Clear existing debounce timer
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    // Set up max wait timer if not already running
    if (!this.maxWaitTimer) {
      const remainingWait = MAX_WAIT - timeSinceLastUpdate
      this.maxWaitTimer = setTimeout(() => {
        this.updatePreviewAndResetTimers()
      }, remainingWait)
    }

    // Set new debounce timer
    this.debounceTimer = setTimeout(() => {
      this.updatePreviewAndResetTimers()
    }, DEBOUNCE_DELAY)
  }

  clearTimers() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
      this.debounceTimer = null
    }
    if (this.maxWaitTimer) {
      clearTimeout(this.maxWaitTimer)
      this.maxWaitTimer = null
    }
  }

  async updatePreviewAndResetTimers() {
    this.clearTimers()
    this.lastUpdateTime = Date.now()

    // Save content and update preview in parallel
    await Promise.all([
      this.saveContent(),
      this.updatePreview()
    ])
  }

  async saveContent() {
    if (!this.hasSaveUrlValue || !this.hasCsrfTokenValue) {
      return // No save URL configured, skip saving
    }

    const html = this.editor.getValue()

    try {
      const response = await fetch(this.saveUrlValue, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-CSRF-Token': this.csrfTokenValue,
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: new URLSearchParams({
          'template[html_content]': html
        })
      })

      if (response.ok) {
        this.showSaveStatus()
      } else {
        console.warn('Failed to save content:', response.statusText)
      }
    } catch (error) {
      console.error('Failed to save content:', error)
    }
  }

  showSaveStatus() {
    if (!this.hasSaveStatusTarget) return

    // Show the "Saved" indicator
    this.saveStatusTarget.classList.remove('d-none')

    // Hide it after 2 seconds
    setTimeout(() => {
      this.saveStatusTarget.classList.add('d-none')
    }, 2000)
  }

  async updatePreview() {
    const html = this.editor.getValue()

    try {
      // Build URL with content as query parameter
      const url = new URL(this.previewUrlValue, window.location.origin)
      url.searchParams.set('content', html)

      // Fetch preview
      const response = await fetch(url)

      // Get the HTML response (includes errors in development mode)
      const previewHtml = await response.text()

      // Update iframe content (will show error trace in dev or preview in prod)
      const iframe = this.previewTarget
      const iframeDoc = iframe.contentDocument || iframe.contentWindow.document
      iframeDoc.open()
      iframeDoc.write(previewHtml)
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

  // Image upload for HTML editor
  openImageModal() {
    if (this.hasImageModalTarget) {
      const modal = new bootstrap.Modal(this.imageModalTarget)
      modal.show()
    }
  }

  triggerImageUpload() {
    this.imageUploadTarget.click()
  }

  async handleImageUpload(event) {
    const file = event.target.files[0]
    if (!file) return

    const formData = new FormData()
    formData.append('file', file)

    try {
      // Show uploading status
      const statusEl = this.imageModalTarget.querySelector('.upload-status')
      if (statusEl) {
        statusEl.textContent = 'Uploading...'
        statusEl.classList.remove('d-none', 'text-danger')
        statusEl.classList.add('text-info')
      }

      // Upload the file
      const response = await fetch(this.uploadUrlValue, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': this.csrfTokenValue,
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: formData
      })

      const data = await response.json()

      if (data.success) {
        // Show the URL in the input
        if (this.hasImageUrlTarget) {
          this.imageUrlTarget.value = data.url
        }

        if (statusEl) {
          statusEl.textContent = 'Upload successful!'
          statusEl.classList.remove('text-info', 'text-danger')
          statusEl.classList.add('text-success')
        }
      } else {
        if (statusEl) {
          statusEl.textContent = `Upload failed: ${data.errors.join(', ')}`
          statusEl.classList.remove('text-info', 'text-success')
          statusEl.classList.add('text-danger')
        }
      }
    } catch (error) {
      console.error('Upload failed:', error)
      const statusEl = this.imageModalTarget.querySelector('.upload-status')
      if (statusEl) {
        statusEl.textContent = 'Upload failed. Please try again.'
        statusEl.classList.remove('text-info', 'text-success')
        statusEl.classList.add('text-danger')
      }
    }

    // Clear the file input
    event.target.value = ''
  }

  insertImage() {
    if (!this.hasImageUrlTarget) return

    const url = this.imageUrlTarget.value.trim()
    if (!url) {
      alert('Please enter or upload an image URL')
      return
    }

    // Insert image tag at cursor position
    const imageTag = `<img src="${url}" alt="Image" style="max-width: 100%; height: auto;">`
    this.editor.replaceSelection(imageTag)
    this.editor.focus()

    // Clear the input and close modal
    this.imageUrlTarget.value = ''
    const statusEl = this.imageModalTarget.querySelector('.upload-status')
    if (statusEl) {
      statusEl.textContent = ''
      statusEl.classList.add('d-none')
    }

    // Close the modal
    const modal = bootstrap.Modal.getInstance(this.imageModalTarget)
    if (modal) {
      modal.hide()
    }

    // Trigger preview update
    this.debouncedUpdatePreview()
  }
}
