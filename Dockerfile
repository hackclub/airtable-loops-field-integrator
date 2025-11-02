FROM ruby:3.3

# Install dependencies
RUN apt-get update -qq && apt-get install -y \
    postgresql-client \
    nodejs \
    npm \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install bundler (matching Gemfile.lock version)
RUN gem install bundler -v 2.7.2

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock* ./

# Configure bundler to use system path
RUN bundle config set --local path /usr/local/bundle

# Install gems
RUN bundle install --jobs 4 --retry 3

# Copy entrypoint script
COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]

# Expose port
EXPOSE 3000

# Default command
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
