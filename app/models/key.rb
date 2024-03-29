require 'digest/md5'

class Key < ActiveRecord::Base
  include AfterCommitQueue
  include Sortable

  belongs_to :user

  before_validation :generate_fingerprint

  validates :title, presence: true, length: { within: 0..255 }
  validates :key, presence: true, length: { within: 0..5000 }, format: { with: /\A(ssh|ecdsa)-.*\Z/ }
  validates :key, format: { without: /\n|\r/, message: '应该是单行' }
  validates :fingerprint, uniqueness: true, presence: { message: '无法生成' }

  delegate :name, :email, to: :user, prefix: true

  after_create :add_to_shell
  after_create :notify_user
  after_create :post_create_hook
  after_destroy :remove_from_shell
  after_destroy :post_destroy_hook

  def key=(value)
    value.strip! unless value.blank?
    write_attribute(:key, value)
  end

  def publishable_key
    # Strip out the keys comment so we don't leak email addresses
    # Replace with simple ident of user_name (hostname)
    self.key.split[0..1].push("#{self.user_name} (#{Gitlab.config.gitlab.host})").join(' ')
  end

  # projects that has this key
  def projects
    user.authorized_projects
  end

  def shell_id
    "key-#{id}"
  end

  def add_to_shell
    GitlabShellWorker.perform_async(
      :add_key,
      shell_id,
      key
    )
  end

  def notify_user
    run_after_commit { NotificationService.new.new_key(self) }
  end

  def post_create_hook
    SystemHooksService.new.execute_hooks_for(self, :create)
  end

  def remove_from_shell
    GitlabShellWorker.perform_async(
      :remove_key,
      shell_id,
      key,
    )
  end

  def post_destroy_hook
    SystemHooksService.new.execute_hooks_for(self, :destroy)
  end

  private

  def generate_fingerprint
    self.fingerprint = nil

    return unless self.key.present?

    self.fingerprint = Gitlab::KeyFingerprint.new(self.key).fingerprint
  end
end
