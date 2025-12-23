class SetupController < ApplicationController
  before_action :authenticate_user!
  before_action :redirect_if_setup_complete

  # GET /setup or /setup?step=1
  def show
    @account = current_account
    @step = params[:step]&.to_i || 1
  end

  # POST /setup
  def update
    @account = current_account
    @step = params[:step]&.to_i || 1

    case @step
    when 1
      update_step_1
    when 2
      update_step_2
    when 3
      update_step_3
    else
      redirect_to setup_path(step: 1)
    end
  end

  private

  def update_step_1
    if @account.update(step_1_params)
      redirect_to setup_path(step: 2), notice: "Account details saved. Now let's configure AWS SES."
    else
      @step = 1
      render :show, status: :unprocessable_entity
    end
  end

  def update_step_2
    @account.assign_attributes(step_2_params)

    if @account.save
      # Test SES connection
      quota_checker = Ses::QuotaChecker.new(@account)
      result = quota_checker.test_connection

      if result[:success]
        # Refresh quota immediately
        @account.refresh_ses_quota!
        redirect_to setup_path(step: 3), notice: "SES credentials verified! Now let's add your logo."
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

  def update_step_3
    # Attach logo if provided
    if params[:account] && params[:account][:logo].present?
      @account.logo.attach(params[:account][:logo])
    end

    # Mark setup as complete
    @account.setup_completed = true

    if @account.save
      redirect_to dashboard_path, notice: "Setup complete! Welcome to Fuegomail."
    else
      @step = 3
      render :show, status: :unprocessable_entity
    end
  end

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
