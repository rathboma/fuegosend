# Implementation & Documentation Plan: Automated Risk Management System

**Goal:** Implement a self-managed anti-abuse system that isolates risk and automates spam detection without manual human oversight.

## Part 1: Technical Requirements

### 1. Domain Segmentation (Reputation Isolation)
**Objective:** Prevent Free users from damaging the sending reputation of Paid users.

* **Infrastructure:** Configure the application to handle tracking links (clicks/opens) across three distinct domain tiers.
    * **Tier 1 (Disposable):** A pool of low-trust domains (e.g., `links-cluster-a.com`) for **Free Plan** users.
    * **Tier 2 (Premium):** A high-trust domain (e.g., `track.yourapp.com`) for **Paid Plan** users ($29/$59).
    * **Tier 3 (Custom):** Support for CNAME records (e.g., `links.brand.com`) for **Agency/High-Volume** users ($99).
* **Routing Logic:** When generating email content:
    * Check `Account.plan`.
    * Inject the corresponding domain base URL for all tracking pixels and wrapped links.
    * Ensure the web server (Nginx/Rails/Node) accepts traffic from *all* configured domains.

### 2. Campaign State Machine
The `Campaign` model requires a strict state machine to manage the automated review flow.

* **`draft`**: User is editing.
* **`queued_for_review`**: User clicked send; waiting out the initial Sandbox Timer.
* **`canary_processing`**: Initial sample batch sent; waiting out the Analysis Timer.
* **`approved`**: Security checks passed; remaining emails are sending.
* **`suspended`**: Security checks failed; account locked.

### 3. The "Sandbox & Canary" Workflow (Free Plan Only)
**Logic:** All campaigns sent by users on the **Free Plan** must pass through this automated gate. Paid users bypass this and go straight to `approved`/sending.

#### Phase A: The "Cool Down" Delay
* **Trigger:** User clicks "Send".
* **Action:** Change status to `queued_for_review`.
* **Timer:** Enforce a **30-minute wait**. No emails leave the system yet.
* **Purpose:** Catches "hit-and-run" spammers who expect instant results.

#### Phase B: The "Canary" Sample
* **Trigger:** 30-minute timer expires.
* **Condition:** If List Size > 500 contacts (smaller lists skip to Phase D but are monitored by the Kill Switch).
* **Action:**
    1.  Select a random sample of **100 contacts**.
    2.  Change status to `canary_processing`.
    3.  Dispatch emails **only** to these 100 recipients.
    4.  Start a second **30-minute Analysis Timer**.

#### Phase C: The Analysis & Decision
* **Trigger:** 30-minute Analysis Timer expires.
* **Input:** Check Amazon SES Webhook data specifically for the 100 Canary emails.
* **Thresholds (Strict):**
    * **Hard Bounce Rate:** > 5% (More than 5 bounces).
    * **Complaint Rate:** > 1% (More than 1 complaint).
* **Outcome:**
    * **FAIL:** Set status to `suspended`. Trigger internal alert. **Do not send remaining emails.**
    * **PASS:** Set status to `approved`. Immediately trigger the job to send the rest of the list.

#### Phase D: The Emergency Kill-Switch (Global)
* **Scope:** Active for *all* users (Free & Paid) during the entire sending process.
* **Logic:** If the webhook processor detects **> 10 Hard Bounces** (absolute count) or **> 2 Complaints** cumulative for a single campaign:
    * **Action:** Immediate Stop.
    * **State:** Transition to `suspended`.
    * **Note:** This overrides any timers.

### 4. User Constraints (Free Plan Hardening)
* **Single Segment:** Free users are limited to 1 List/Segment.
* **Import Throttling:** Imported contacts remain in a `pending_validation` state for 30 minutes before they can be added to a campaign.
* **Recurrence:** Since the Free plan is a "risk" tier, **ALL** campaigns sent on the Free plan go through this 30+30 minute process. This friction is intentional—it encourages legitimate businesses to upgrade to the $29 plan for "Instant Sending."

---

## Part 2: Documentation & Communication Guidelines

**Strategy:** Frame these restrictions as "Deliverability Optimization" and "Security Checks" rather than lack of trust.

### 1. UI Status Messages
Do not use words like "Delayed," "Hold," or "Probation." Use "Processing" terminology.

* **During the first 30 mins:**
    * *Display:* `Status: Queued for Delivery`
    * *Tooltip:* "Your campaign is queued in our outbound mail server."
* **During the Canary Phase:**
    * *Display:* `Status: Sending & Verifying`
    * *Tooltip:* "Initial batch dispatched. Verifying ISP acceptance rates."

### 2. Knowledge Base / Docs

**Topic: Campaign Sending Speeds**
> **"Why is my campaign status 'Queued'?"**
> To maintain the highest possible reputation with email providers (Gmail, Outlook), our system utilizes a **Smart Queuing Algorithm**.
>
> * **Free Tier:** Campaigns undergo a standard **Health Check** (approx. 30–60 minutes) where a small portion of emails are sent first to verify list quality. If metrics look good, the rest are released automatically. This prevents your domain from being blocked by spam filters.
> * **Starter / Pro Tiers:** Verified accounts bypass the Health Check queue and enjoy **Instant Dispatch**.

**Topic: Tracking Links**
> **"How tracking links affect delivery"**
> * **Free Accounts:** Use our shared pool of tracking domains. These are rotated regularly to ensure uptime.
> * **Pro/Agency Accounts:** Can connect a **Custom Domain** (e.g., `links.yourbrand.com`). This is highly recommended as it builds trust with your subscribers and improves inbox placement.

**Topic: Acceptable Use (The "Suspended" Explanation)**
> **"Why was my campaign paused?"**
> Our system monitors real-time feedback from Amazon SES. If a campaign generates a bounce rate exceeding industry safety standards (typically >5%), the system will automatically pause sending to protect your account from a permanent AWS ban.
>
> *Recommendation:* Please use a list verification tool to clean your contacts before attempting to send again.

### 3. FAQ Section

**Q: Can I request a manual review to speed up the Free tier?**
> **A:** The Health Check process is fully automated and cannot be bypassed manually. For time-sensitive campaigns, we recommend upgrading to the **Starter Plan ($29/mo)** which enables Instant Dispatch.

**Q: Do I need to wait 60 minutes for every email?**
> **A:** On the Free plan, yes. This automated "warm-up" process is essential for maintaining the free infrastructure. Paid plans do not have this delay.