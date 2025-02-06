require_relative './lib/client'
require_relative './lib/pull_request'
require 'csv'

TEAM_NAME = "Shopify/payments-infrastructure"

GITHUB_USERNAMES = %w[
  Smittttty
  abalmeida7
  Anasshahidd21
  Wryte
  indominus-joe
  nSanjari
  nicholashhchen
  owenlintonAD
].freeze

class OverallMetricsAnalyzer
  def initialize
    @client = Client.new
    @prs = nil
  end

  def analyze
    puts "\nFetching all PR data..."
    fetch_all_prs
    
    puts "\nAnalyzing combined PR set..."
    reviewed_prs = @prs.select { |pr| has_team_review?(pr) }
    merged_reviewed_prs = reviewed_prs.select(&:merged?)
    
    results = {
      unique_reviewed_prs: reviewed_prs.count,
      timing: calculate_timing_metrics(reviewed_prs, merged_reviewed_prs),
      review_distribution: calculate_review_distribution(merged_reviewed_prs)
    }

    print_results(results)
    export_to_csv(results)
    results
  end

  private

  def fetch_all_prs
    team_prs = fetch_team_prs
    direct_prs = fetch_direct_prs
    
    puts "Team-tagged PRs: #{team_prs.count}"
    puts "Direct-tagged PRs: #{direct_prs.count}"
    
    @prs = (team_prs + direct_prs).uniq { |pr| pr.url }
    puts "Total unique PRs: #{@prs.count}"
  end

  def fetch_team_prs
    raw_prs = @client.fetch_team_tagged_prs(TEAM_NAME)
    raw_prs.map { |pr_data| PullRequest.new(pr_data) }
  end

  def fetch_direct_prs
    all_prs = []
    GITHUB_USERNAMES.each do |username|
      puts "Fetching direct reviews for #{username}..."
      raw_prs = @client.fetch_all_prs_direct_reviews(username)
      all_prs.concat(raw_prs.map { |pr_data| PullRequest.new(pr_data) })
    end
    all_prs
  end

  def has_team_review?(pr)
    GITHUB_USERNAMES.any? { |username| pr.engaged_by?(username) }
  end

  def calculate_timing_metrics(reviewed_prs, merged_prs)
    first_review_times = reviewed_prs.map { |pr|
      first_review = find_first_review_time(pr)
      if first_review
        request_time = pr.team_review_requested_at || pr.created_at
        business_hours_between(request_time, first_review)
      end
    }.compact

    second_review_times = reviewed_prs.map { |pr|
      second_review = find_second_review_time(pr)
      if second_review
        request_time = pr.team_review_requested_at || pr.created_at
        business_hours_between(request_time, second_review)
      end
    }.compact
    
    merge_times = merged_prs.map { |pr|
      request_time = pr.team_review_requested_at || pr.created_at
      business_hours_between(request_time, pr.merged_at)
    }.compact

    puts "\nTiming Debug:"
    puts "First review times found: #{first_review_times.count}"
    puts "Second review times found: #{second_review_times.count}"
    puts "Merge times found: #{merge_times.count}"

    {
      first_review: {
        average: calculate_average(first_review_times),
        p90: calculate_percentile(first_review_times, 90)
      },
      second_review: {
        average: calculate_average(second_review_times),
        p90: calculate_percentile(second_review_times, 90)
      },
      merge: {
        average: calculate_average(merge_times),
        p90: calculate_percentile(merge_times, 90)
      }
    }
  end

  def find_first_review_time(pr)
    review_times = GITHUB_USERNAMES.map { |username| 
      pr.first_engagement_at(username)
    }.compact
    review_times.min
  end

  def find_second_review_time(pr)
    review_times = GITHUB_USERNAMES.map { |username| 
      pr.first_engagement_at(username)
    }.compact.sort
    review_times[1] if review_times.length >= 2
  end

  def calculate_review_distribution(merged_prs)
    review_counts = merged_prs.map do |pr|
      reviewer_count = GITHUB_USERNAMES.count { |username| pr.engaged_by?(username) }
      puts "\nPR #{pr.url}: #{reviewer_count} team reviewers"
      reviewer_count
    end

    total = merged_prs.count.to_f
    
    puts "\nReview count distribution:"
    puts "1 review: #{review_counts.count(1)}"
    puts "2 reviews: #{review_counts.count(2)}"
    puts "3+ reviews: #{review_counts.count { |count| count > 2 }}"

    {
      one_review: {
        count: review_counts.count(1),
        percentage: calculate_percentage(review_counts.count(1), total)
      },
      two_reviews: {
        count: review_counts.count(2),
        percentage: calculate_percentage(review_counts.count(2), total)
      },
      more_than_two: {
        count: review_counts.count { |count| count > 2 },
        percentage: calculate_percentage(review_counts.count { |count| count > 2 }, total)
      }
    }
  end

  def print_results(results)
    puts "\nOverall Team Metrics:"
    puts "Unique PRs with reviews: #{results[:unique_reviewed_prs]}"
    
    puts "\nTiming Metrics:"
    puts "First Review: avg #{results[:timing][:first_review][:average]}h, p90 #{results[:timing][:first_review][:p90]}h"
    puts "Second Review: avg #{results[:timing][:second_review][:average]}h, p90 #{results[:timing][:second_review][:p90]}h"
    puts "Time to Merge: avg #{results[:timing][:merge][:average]}h, p90 #{results[:timing][:merge][:p90]}h"
    
    puts "\nReview Distribution:"
    puts "1 review: #{results[:review_distribution][:one_review][:count]} PRs (#{results[:review_distribution][:one_review][:percentage]}%)"
    puts "2 reviews: #{results[:review_distribution][:two_reviews][:count]} PRs (#{results[:review_distribution][:two_reviews][:percentage]}%)"
    puts "2+ reviews: #{results[:review_distribution][:more_than_two][:count]} PRs (#{results[:review_distribution][:more_than_two][:percentage]}%)"
  end

  def export_to_csv(results)
    CSV.open("overall_metrics.csv", "wb") do |csv|
      csv << ["Metric", "Value"]
      csv << ["Unique PRs with reviews", results[:unique_reviewed_prs]]
      csv << ["Average time to first review", "#{results[:timing][:first_review][:average]}h"]
      csv << ["P90 time to first review", "#{results[:timing][:first_review][:p90]}h"]
      csv << ["Average time to second review", "#{results[:timing][:second_review][:average]}h"]
      csv << ["P90 time to second review", "#{results[:timing][:second_review][:p90]}h"]
      csv << ["Average time to merge", "#{results[:timing][:merge][:average]}h"]
      csv << ["P90 time to merge", "#{results[:timing][:merge][:p90]}h"]
      csv << ["PRs with 1 review", "#{results[:review_distribution][:one_review][:count]} (#{results[:review_distribution][:one_review][:percentage]}%)"]
      csv << ["PRs with 2 reviews", "#{results[:review_distribution][:two_reviews][:count]} (#{results[:review_distribution][:two_reviews][:percentage]}%)"]
      csv << ["PRs with 2+ reviews", "#{results[:review_distribution][:more_than_two][:count]} (#{results[:review_distribution][:more_than_two][:percentage]}%)"]
    end
  end

  def calculate_percentage(numerator, denominator)
    return 0.0 if denominator.zero?
    (numerator.to_f / denominator * 100).round(2)
  end

  def calculate_average(values)
    return 0.0 if values.empty?
    (values.sum / values.length).round(2)
  end

  def calculate_percentile(values, percentile)
    return 0.0 if values.empty?
    sorted = values.sort
    k = (percentile / 100.0 * (sorted.length - 1)).round
    sorted[k].round(2)
  end

  def business_hours_between(start_time, end_time)
    return nil unless start_time && end_time
    
    business_hours = 0
    current_time = start_time
  
    while current_time < end_time
      if current_time.wday != 0 && current_time.wday != 6
        if current_time.hour.between?(9, 16)
          business_hours += 1
        end
      end
      current_time += 3600
    end
  
    business_hours.round(2)
  end
end

if __FILE__ == $PROGRAM_NAME
  analyzer = OverallMetricsAnalyzer.new
  analyzer.analyze
end