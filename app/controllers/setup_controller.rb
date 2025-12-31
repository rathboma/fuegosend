class SetupController < ApplicationController
  before_action :authenticate_user!
  before_action :redirect_if_setup_complete

  # GET /setup
  def show
    @account = current_account
    @step = @account.current_setup_step || 1

    # If setup is complete, redirect to dashboard
    redirect_to dashboard_path if @step.nil?
  end

  # POST /setup/account_details
  def account_details
    @account = current_account

    if @account.update(step_1_params)
      @account.setup_step_account_details!
      redirect_to setup_path, notice: "Account details saved. Now let's configure AWS SES."
    else
      @step = 1
      render :show, status: :unprocessable_entity
    end
  end

  # POST /setup/aws_credentials
  def aws_credentials
    @account = current_account
    @account.assign_attributes(step_2_params)

    if @account.save
      # Test SES connection
      quota_checker = Ses::QuotaChecker.new(@account)
      result = quota_checker.test_connection

      if result[:success]
        # Refresh quota and advance to next step
        @account.refresh_ses_quota!
        @account.setup_step_aws_credentials!
        redirect_to setup_path, notice: "SES credentials verified! Now let's add your logo."
      else
        @account.errors.add(:base, "SES connection failed: #{result[:error]}")
        @step = 2
        render :show, status: :unprocessable_entity
      end
    else
      @step = 2
      render :show, status: :unprocessable_entity
    end
  end

  # POST /setup/logo
  def logo
    @account = current_account

    # Attach logo if provided
    if params[:account] && params[:account][:logo].present?
      @account.logo.attach(params[:account][:logo])
    end

    # Mark setup as complete
    @account.setup_step_complete!

    redirect_to dashboard_path, notice: "Setup complete! Welcome to Fuegomail."
  end

  # POST /setup/skip_logo
  def skip_logo
    @account = current_account
    @account.setup_step_complete!
    redirect_to dashboard_path, notice: "Setup complete! You can add your logo later in Account Settings."
  end

  private

  def step_1_params
    params.require(:account).permit(:name, :subdomain)
  end

  def step_2_params
    params.require(:account).permit(:aws_access_key_id, :aws_secret_access_key, :aws_region)
  end

  def redirect_if_setup_complete
    redirect_to dashboard_path if current_account.setup_complete?
  end

  def current_account
    @current_account ||= current_user.account
  end
  helper_method :current_account
end
