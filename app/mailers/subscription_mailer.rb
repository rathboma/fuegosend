class SubscriptionMailer < ApplicationMailer
  # Send confirmation email for double opt-in
  def confirm_subscription(subscriber, list)
    @subscriber = subscriber
    @list = list
    @account = list.account

    # Generate confirmation token
    verifier = Rails.application.message_verifier(:subscription_confirmation)
    @confirmation_token = verifier.generate({
      subscriber_id: subscriber.id,
      list_id: list.id
    })

    # Generate confirmation URL
    @confirmation_url = confirm_subscription_url(@confirmation_token)

    mail(
      to: subscriber.email,
      subject: "Please confirm your subscription to #{list.name}",
      from: "#{@account.name} <noreply@#{Rails.application.config.action_mailer.default_url_options[:host]}>"
    )
  end
end
