require 'bundler/setup'
require 'json'
require 'open3'

class Client
  MAX_RETRIES = 10
  RETRY_DELAY = 2 # in seconds
  BOTS = %w[
    github-actions[bot]
    shopify-shipitnext[bot]
    dependabot[bot]
  ].freeze

  def initialize
    @client = gh_executable
  end

  def fetch_all_prs_direct_reviews(username)
    all_prs = []
    
    all_prs.concat(fetch_individual_tagged_prs("review-requested:#{username} type:pr -is:archived -is:closed"))
    all_prs.concat(fetch_individual_tagged_prs("reviewed-by:#{username} type:pr -is:archived -is:closed"))
    
    all_prs.uniq { |pr| pr['url'] }
  end

  def fetch_team_tagged_prs(team_name)
    fetched_prs = []
    cursor = nil
    bot_exclusions = BOTS.map { |bot| "-author:#{bot}" }.join(" ")
    
    while fetched_prs.length < 100
      query = build_team_query(team_name, cursor, bot_exclusions)
      result = execute_query(query)
      
      valid_prs = result[:prs].select do |pr|
        pr['state'] == 'OPEN' || pr['state'] == 'MERGED'
      end
      
      fetched_prs.concat(valid_prs)
      
      break unless result[:page_info]['hasNextPage'] && fetched_prs.length < 100
      cursor = result[:page_info]['endCursor']
    end
    
    fetched_prs
  end

  private

  def gh_executable
    gh_path = `which gh`.strip
    raise "GitHub CLI not found. Please install it with: brew install gh" if gh_path.empty?
    gh_path
  end

  def execute_query(query)
    attempts = 0
  
    while attempts < MAX_RETRIES
      begin
        stdout, stderr, status = Open3.capture3(
          @client,
          "api",
          "graphql",
          "-f", 
          "query=#{query}"
        )
        
        raise "GitHub CLI error: #{stderr}" unless status.success?
        response = JSON.parse(stdout)
        
        return {
          prs: response.dig('data', 'search', 'nodes') || [],
          page_info: response.dig('data', 'search', 'pageInfo')
        }
      rescue => error
        attempts += 1
        raise error if attempts == MAX_RETRIES
        sleep RETRY_DELAY
      end
    end
  end

  def fetch_individual_tagged_prs(search_query)
    fetched_prs = []
    cursor = nil

    while fetched_prs.length < 50
      query = build_individual_query(search_query, cursor)
      result = execute_query(query)
      fetched_prs.concat(result[:prs])

      break unless result[:page_info]['hasNextPage'] && fetched_prs.length < 50
      cursor = result[:page_info]['endCursor']
    end

    fetched_prs
  end

  def build_individual_query(search_query, cursor)
    <<~GQL
      query {
        search(
          query: "#{search_query}"
          type: ISSUE
          first: 50
          #{cursor ? "after: \"#{cursor}\"" : nil}
        ) {
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            ... on PullRequest {
              number
              url
              state
              createdAt
              mergedAt
              author {
                login
              }
              reviewRequests(first: 20) {
                nodes {
                  requestedReviewer {
                    ... on Team {
                      name
                      slug
                    }
                  }
                }
              }
              timelineItems(first: 20, itemTypes: [REVIEW_REQUESTED_EVENT]) {
                nodes {
                  ... on ReviewRequestedEvent {
                    createdAt
                    requestedReviewer {
                      ... on User {
                        login
                      }
                    }
                  }
                }
              }
              reviews(first: 20) {
                nodes {
                  author {
                    login
                  }
                  state
                  createdAt
                }
              }
              comments(first: 20) {
                nodes {
                  author {
                    login
                  }
                  createdAt
                }
              }
              reviewThreads(first: 20) {
                nodes {
                  comments(first: 20) {
                    nodes {
                      author {
                        login
                      }
                      createdAt
                    }
                  }
                }
              }
            }
          }
        }
      }
    GQL
  end

  def build_team_query(team_name, cursor, bot_exclusions)
    <<~GQL
      query {
        search(
          query: "team-review-requested:#{team_name} type:pr -is:archived -is:closed #{bot_exclusions}"
          type: ISSUE
          first: 100,
          #{cursor ? "after: \"#{cursor}\"" : nil}
        ) {
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            ... on PullRequest {
              number
              url
              state
              createdAt
              mergedAt
              author {
                login
              }
              reviewRequests(first: 20) {
                nodes {
                  requestedReviewer {
                    ... on Team {
                      name
                      slug
                    }
                  }
                }
              }
              reviews(first: 20) {
                nodes {
                  author {
                    login
                  }
                  state
                  createdAt
                }
              }
              comments(first: 20) {
                nodes {
                  author {
                    login
                  }
                  createdAt
                }
              }
              reviewThreads(first: 20) {
                nodes {
                  comments(first: 20) {
                    nodes {
                      author {
                        login
                      }
                      createdAt
                    }
                  }
                }
              }
            }
          }
        }
      }
    GQL
  end
end