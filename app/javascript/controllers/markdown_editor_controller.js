import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "hiddenField", "preview", "saveStatus", "toolbar", "imageUpload", "editorCard", "subscriberSearch", "subscriberResults", "selectedSubscriber"]
  static values = {
    previewUrl: String,
    saveUrl: String,
    csrfToken: String,
    uploadUrl: String,
    initialSubscriberId: String
  }

  connect() {
    this.debounceTimer = null
    this.maxWaitTimer = null
    this.lastUpdateTime = Date.now()
    this.selectedSubscriberId = this.initialSubscriberIdValue || null
    this.searchDebounce = null
    this.waitForCodeMirror().then(() => {
      this.initializeEditor()
      this.updatePreviewHeight()
    })
    // Update preview height on window resize
    window.addEventListener('resize', () => this.updatePreviewHeight())
  }

  disconnect() {
    window.removeEventListener('resize', () => this.updatePreviewHeight())
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
    if (this.searchDebounce) {
      clearTimeout(this.searchDebounce)
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
      theme: 'eclipse',
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

    const markdown = this.editor.getValue()

    try {
      const response = await fetch(this.saveUrlValue, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-CSRF-Token': this.csrfTokenValue,
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: new URLSearchParams({
          'campaign[body_markdown]': markdown,
          'campaign[step]': '2'
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
    const markdown = this.editor.getValue()

    try {
      // Build URL with content as query parameter
      const url = new URL(this.previewUrlValue, window.location.origin)
      url.searchParams.set('content', markdown)

      // Include selected subscriber if set
      if (this.selectedSubscriberId) {
        url.searchParams.set('subscriber_id', this.selectedSubscriberId)
      }

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

  // Formatting actions
  bold() {
    this.wrapSelection('**', '**')
  }

  italic() {
    this.wrapSelection('*', '*')
  }

  heading1() {
    this.insertAtLineStart('# ')
  }

  heading2() {
    this.insertAtLineStart('## ')
  }

  heading3() {
    this.insertAtLineStart('### ')
  }

  link() {
    const selection = this.editor.getSelection()
    const text = selection || 'link text'
    const replacement = `[${text}](https://example.com)`
    this.editor.replaceSelection(replacement)

    // Select the URL for easy editing
    const cursor = this.editor.getCursor()
    const line = cursor.line
    const urlStart = cursor.ch - 20 // Position of "https"
    const urlEnd = cursor.ch - 1    // Position before ")"
    this.editor.setSelection(
      { line: line, ch: urlStart },
      { line: line, ch: urlEnd }
    )
    this.editor.focus()
  }

  // Image upload
  triggerImageUpload() {
    this.imageUploadTarget.click()
  }

  async handleImageUpload(event) {
    const file = event.target.files[0]
    if (!file) return

    const formData = new FormData()
    formData.append('file', file)

    // Show uploading status
    const uploadingText = `![Uploading ${file.name}...]()`
    this.editor.replaceSelection(uploadingText)
    this.editor.focus()

    try {
      // Upload the file
      const response = await fetch(this.uploadUrlValue, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': this.csrfTokenValue,
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: formData
      })

      // Check if response is JSON
      const contentType = response.headers.get('content-type')
      if (!contentType || !contentType.includes('application/json')) {
        throw new Error('Server returned an error. Please try again.')
      }

      const data = await response.json()

      if (data.success) {
        // Replace uploading text with actual image
        const content = this.editor.getValue()
        const updatedContent = content.replace(
          uploadingText,
          `![${file.name}](${data.url})`
        )
        this.editor.setValue(updatedContent)
        this.editor.focus()

        // Trigger preview update
        this.debouncedUpdatePreview()
      } else {
        alert(`Upload failed: ${data.errors.join(', ')}`)
        // Remove uploading text
        const content = this.editor.getValue()
        const updatedContent = content.replace(uploadingText, '')
        this.editor.setValue(updatedContent)
      }
    } catch (error) {
      console.error('Upload failed:', error)
      alert('Upload failed. Please try again.')
      // Remove uploading text on error
      const content = this.editor.getValue()
      const updatedContent = content.replace(uploadingText, '')
      this.editor.setValue(updatedContent)
    }

    // Clear the file input
    event.target.value = ''
  }

  // Helper methods
  wrapSelection(before, after) {
    const selection = this.editor.getSelection()
    if (selection) {
      this.editor.replaceSelection(before + selection + after)
    } else {
      const cursor = this.editor.getCursor()
      this.editor.replaceSelection(before + 'text' + after)
      // Select 'text' for easy replacement
      this.editor.setSelection(
        { line: cursor.line, ch: cursor.ch + before.length },
        { line: cursor.line, ch: cursor.ch + before.length + 4 }
      )
    }
    this.editor.focus()
  }

  insertAtLineStart(prefix) {
    const cursor = this.editor.getCursor()
    const line = this.editor.getLine(cursor.line)

    // Toggle: remove prefix if it already exists
    if (line.startsWith(prefix)) {
      const newLine = line.substring(prefix.length)
      this.editor.replaceRange(
        newLine,
        { line: cursor.line, ch: 0 },
        { line: cursor.line, ch: line.length }
      )
    } else {
      this.editor.replaceRange(
        prefix,
        { line: cursor.line, ch: 0 }
      )
    }
    this.editor.focus()
  }

  // Insert merge tag
  insertMergeTag(event) {
    event.preventDefault()
    const tag = event.currentTarget.dataset.tag
    if (tag) {
      this.editor.replaceSelection(tag)
      this.editor.focus()
    }
  }

  // Update preview height to match toolbar + editor
  updatePreviewHeight() {
    if (!this.hasToolbarTarget || !this.hasEditorCardTarget || !this.hasPreviewTarget) {
      return
    }

    // Calculate total height of toolbar + editor
    const toolbarHeight = this.toolbarTarget.offsetHeight
    const editorHeight = this.editorCardTarget.offsetHeight

    // Add some margin (toolbar has mb-2 which is ~8px)
    const totalHeight = toolbarHeight + editorHeight + 8

    // Set preview iframe height
    this.previewTarget.style.height = `${totalHeight}px`
  }

  // Prevent form submission on enter in search field
  handleSearchKeydown(event) {
    if (event.key === 'Enter') {
      event.preventDefault()
      return false
    }
  }

  // Search subscribers for preview
  searchSubscribers(event) {
    const query = event.target.value.trim()

    // Clear any existing timeout
    if (this.searchDebounce) {
      clearTimeout(this.searchDebounce)
    }

    // If query is empty, hide results
    if (query.length === 0) {
      this.hideSubscriberResults()
      return
    }

    // Show loading state
    if (this.hasSubscriberResultsTarget) {
      this.subscriberResultsTarget.innerHTML = '<div class="text-muted text-center py-3">Searching...</div>'
    }

    // Debounce the search
    this.searchDebounce = setTimeout(async () => {
      try {
        const response = await fetch(`/campaigns/search_subscribers?q=${encodeURIComponent(query)}`, {
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Accept': 'application/json'
          }
        })

        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`)
        }

        const results = await response.json()
        this.displaySubscriberResults(results)
      } catch (error) {
        console.error('Failed to search subscribers:', error)
        if (this.hasSubscriberResultsTarget) {
          this.subscriberResultsTarget.innerHTML = '<div class="text-danger text-center py-3">Search failed. Please try again.</div>'
        }
      }
    }, 300)
  }

  displaySubscriberResults(results) {
    if (!this.hasSubscriberResultsTarget) return

    if (!results || results.length === 0) {
      this.subscriberResultsTarget.innerHTML = '<div class="text-muted text-center py-3">No subscribers found</div>'
      return
    }

    const html = results.map(result => {
      // Escape HTML to prevent XSS
      const escapedDisplay = this.escapeHtml(result.display)
      const escapedEmail = this.escapeHtml(result.email)

      return `
        <a class="list-group-item list-group-item-action" href="#"
           data-subscriber-id="${result.id}"
           data-subscriber-email="${escapedEmail}"
           data-action="click->markdown-editor#selectSubscriber">
          ${escapedDisplay}
        </a>
      `
    }).join('')

    this.subscriberResultsTarget.innerHTML = html
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  hideSubscriberResults() {
    if (this.hasSubscriberResultsTarget) {
      this.subscriberResultsTarget.innerHTML = '<div class="text-muted text-center py-3">Type to search for subscribers</div>'
    }
  }

  selectSubscriber(event) {
    event.preventDefault()

    const subscriberId = event.currentTarget.dataset.subscriberId
    const subscriberEmail = event.currentTarget.dataset.subscriberEmail

    // Store selected subscriber on ALL instances of this controller
    const allControllers = this.application.controllers.filter(c => c.identifier === 'markdown-editor')

    allControllers.forEach(controller => {
      controller.selectedSubscriberId = subscriberId

      // Update display if target exists
      if (controller.hasSelectedSubscriberTarget) {
        controller.selectedSubscriberTarget.textContent = `Preview with: ${subscriberEmail}`
      }

      // Update preview if it has the method
      if (controller.hasPreviewTarget && controller.updatePreview) {
        controller.updatePreview()
      }
    })

    // Clear search input
    if (this.hasSubscriberSearchTarget) {
      this.subscriberSearchTarget.value = ''
    }

    // Hide results
    this.hideSubscriberResults()

    // Close modal
    const modal = bootstrap.Modal.getInstance(document.getElementById('subscriberSelectModal'))
    if (modal) {
      modal.hide()
    }
  }
}
