# frozen_string_literal: true

module RuboCop
  # A wrapper around patterns array to perform optimized search.
  #
  # For projects with a large set of rubocop todo files, most items in `Exclude`/`Include`
  # are exact file names. It is wasteful to linearly check the list of patterns over and over
  # to check if the file is relevant to the cop.
  #
  # This class partitions an array of patterns into a set of exact match strings and the rest
  # of the patterns. This way we can firstly do a cheap check in the set and then proceed via
  # the costly patterns check, if needed.
  #
  # Patterns are matched against the path form they were written for: absolute patterns
  # (e.g. `Exclude` entries, which are made absolute when the configuration is loaded)
  # against the absolute file path, and relative patterns against the path relative to the
  # configuration. Otherwise a relative pattern like `**/app/**/*.rb` would also match
  # directory components of the project's own parent directories. Regexp patterns may have
  # been written against either form, so they are matched against both.
  # @api private
  class FilePatterns
    @cache = {}.compare_by_identity

    def self.from(patterns)
      @cache[patterns] ||= new(patterns)
    end

    def initialize(patterns)
      @relative_strings = Set.new
      @absolute_strings = Set.new
      @relative_patterns = []
      @absolute_patterns = []
      @match_cache = {}
      partition_patterns(patterns)
    end

    def match?(relative_path, file = relative_path)
      # `FilePatterns.from` memoizes one instance per pattern array (by identity),
      # so this cache is shared across every cop using the same Include/Exclude
      # list. Patterns are immutable within a run, so caching by path is safe.
      cached = @match_cache[file]
      return cached unless cached.nil?

      # A relative path starting with `..` lies outside the configuration's base
      # directory, so relative patterns cannot match it. Match all patterns against
      # the absolute path instead.
      relative_path = File.expand_path(file) if relative_path.start_with?('..')

      @match_cache[file] = found_match?(relative_path, file)
    end

    private

    def found_match?(relative_path, file)
      @relative_strings.include?(relative_path) ||
        @absolute_strings.include?(file) ||
        @relative_patterns.any? { |pattern| PathUtil.match_path?(pattern, relative_path) } ||
        @absolute_patterns.any? { |pattern| PathUtil.match_path?(pattern, file) }
    end

    def partition_patterns(patterns)
      patterns.each do |pattern|
        unless pattern.is_a?(String)
          @relative_patterns << pattern
          @absolute_patterns << pattern
          next
        end

        absolute = PathUtil.absolute?(pattern) || pattern.start_with?('..')
        if pattern.match?(/[*{\[?]/)
          (absolute ? @absolute_patterns : @relative_patterns) << pattern
        else
          (absolute ? @absolute_strings : @relative_strings) << pattern
        end
      end
    end
  end
end
