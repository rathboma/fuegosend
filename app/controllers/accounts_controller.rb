class AccountsController < ApplicationController
  before_action :authenticate_user!

  def show
    @account = current_account
    @ses_quota = {
      sent_today: @account.ses_sent_last_24_hours,
      max_daily: @account.ses_max_24_hour_send,
      max_rate: @account.ses_max_send_rate,
      percent_used: @account.ses_quota_percent_used,
      quota_reset_at: @account.ses_quota_reset_at
    }
  end

  def edit
    @account = current_account
  end

  def update
    @account = current_account

    # Attach logo if provided
    if params[:account] && params[:account][:logo].present?
      @account.logo.attach(params[:account][:logo])
    end

    if @account.update(account_params)
      # Test SES connection if credentials were updated
      if account_params[:aws_access_key_id].present? || account_params[:aws_secret_access_key].present?
        test_ses_connection
      end

      redirect_to account_path, notice: "Account settings updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def current_account
    @current_account ||= current_user.account
  end
  helper_method :current_account

  def account_params
    params.require(:account).permit(
      :name,
      :subdomain,
      :brand_logo,
      :aws_access_key_id,
      :aws_secret_access_key,
      :aws_region
    )
  end

  def test_ses_connection
    quota_checker = Ses::QuotaChecker.new(@account)
    result = quota_checker.test_connection

    if result[:success]
      flash[:notice] = "SES credentials verified successfully!"
      # Refresh quota immediately
      @account.refresh_ses_quota!
    else
      flash[:alert] = "Warning: SES connection test failed: #{result[:error]}"
    end
  end
end
