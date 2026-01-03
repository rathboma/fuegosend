class InvitationMailer < ApplicationMailer
  def invite(invitation)
    @invitation = invitation
    @account = invitation.account
    @invited_by = invitation.invited_by
    @accept_url = accept_invitation_url(invitation.token)

    mail(
      to: invitation.email,
      subject: "#{@invited_by.first_name || @invited_by.email} invited you to join #{@account.name}",
      from: "#{@account.name} <noreply@#{Rails.application.config.action_mailer.default_url_options[:host]}>"
    )
  end
end
