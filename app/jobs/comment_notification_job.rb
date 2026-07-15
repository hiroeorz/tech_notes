class CommentNotificationJob < ApplicationJob
  self.enqueue_after_transaction_commit = true

  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  def perform(comment)
    CommentMailer.new_comment(comment).deliver_now
  end
end
