require 'bundler/setup'
require 'date'
require 'time'

class PullRequest
  attr_reader :data

  def initialize(graphql_data)
    @data = graphql_data
  end
  
  def url
    data['url']
  end

  def state
    data['state']
  end

  def merged?
    state == 'MERGED'
  end

  def created_at
    Time.parse(data['createdAt'])
  end

  def merged_at
    merged? ? Time.parse(data['mergedAt']) : nil
  end

  def engaged_by?(username)
    return false if data.dig('author', 'login') == username
    has_reviews_by?(username) || 
    has_comments_by?(username) || 
    has_thread_comments_by?(username)
  end

  def approved_by?(username)
    data.dig('reviews', 'nodes')&.any? do |review|
      review.dig('author', 'login') == username && 
      review['state'] == 'APPROVED'
    end
  end

  def review_requested_at(username)
    event = data.dig('timelineItems', 'nodes')&.find do |event|
      event.dig('requestedReviewer', 'login') == username
    end
      
    event ? Time.parse(event['createdAt']) : nil
  end

  def team_review_requested_at
    team_request = data.dig('reviewRequests', 'nodes')&.find do |request|
      request.dig('requestedReviewer', 'slug') == 'payments-infrastructure'
    end

    team_request ? Time.parse(data['createdAt']) : nil
  end

  def first_engagement_at(username)
    times = []
  
    data.dig('reviews', 'nodes')&.each do |review|
      if review.dig('author', 'login') == username
        times << Time.parse(review['createdAt'])
      end
    end
  
    data.dig('comments', 'nodes')&.each do |comment|
      if comment.dig('author', 'login') == username
        times << Time.parse(comment['createdAt'])
      end
    end
  
    data.dig('reviewThreads', 'nodes')&.each do |thread|
      thread.dig('comments', 'nodes')&.each do |comment|
        if comment.dig('author', 'login') == username
          times << Time.parse(comment['createdAt'])
        end
      end
    end
  
    times.min
  end

  def first_approval_at(username)
    approval = data.dig('reviews', 'nodes')&.find do |review|
      review.dig('author', 'login') == username && 
      review['state'] == 'APPROVED'
    end
    
    approval ? Time.parse(approval['createdAt']) : nil
  end

  private

  def has_reviews_by?(username)
    data.dig('reviews', 'nodes')&.any? { |review| review.dig('author', 'login') == username }
  end

  def has_comments_by?(username)
    data.dig('comments', 'nodes')&.any? { |comment| comment.dig('author', 'login') == username }
  end

  def has_thread_comments_by?(username)
    data.dig('reviewThreads', 'nodes')&.any? do |thread|
      thread.dig('comments', 'nodes')&.any? { |comment| comment.dig('author', 'login') == username }
    end
  end
end