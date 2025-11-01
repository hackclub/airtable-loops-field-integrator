module Pollable
  extend ActiveSupport::Concern

  def next_interval_with_jitter
    base = poll_interval_seconds
    j = (poll_jitter || 0.10).clamp(0, 1)
    (base * (1.0 + ((rand * 2 - 1) * j))).to_i.clamp(1, 86_400)
  end

  # reservation made by the enqueuer to avoid double-pick
  def reserve_from!(time = Time.current)
    update_columns(
      next_poll_at: time + next_interval_with_jitter,
      updated_at:   Time.current
    )
  end

  def mark_attempt!
    update_columns(last_poll_attempted_at: Time.current)
  end

  def mark_success!
    update_columns(
      last_successful_poll_at: Time.current,
      consecutive_failures:    0,
      error_details:           {},
      updated_at:              Time.current
    )
  end

  def mark_failure!(err_hash, max_backoff: 30.minutes)
    n = consecutive_failures + 1
    penalty = [2**[n, 10].min, 1].max
    update_columns(
      consecutive_failures: n,
      error_details: (error_details || {}).merge(err_hash),
      next_poll_at: [next_poll_at, Time.current].max + [poll_interval_seconds * penalty, max_backoff].min,
      updated_at: Time.current
    )
  end
end


