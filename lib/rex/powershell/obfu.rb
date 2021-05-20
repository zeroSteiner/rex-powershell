# -*- coding: binary -*-

require 'rex/text'

module Rex
module Powershell
  module Obfu
    MULTI_LINE_COMMENTS_REGEX = Regexp.new(/<#(.*?)#>/m)
    SINGLE_LINE_COMMENTS_REGEX = Regexp.new(/^\s*#(?!.*region)(.*$)/i)
    WINDOWS_EOL_REGEX = Regexp.new(/[\r\n]+/)
    UNIX_EOL_REGEX = Regexp.new(/[\n]+/)
    WHITESPACE_REGEX = Regexp.new(/\s+/)
    EMPTY_LINE_REGEX = Regexp.new(/^$|^\s+$/)

    #
    # Obfuscate a Powershell literal string value. The character set of the string is limited to alpha-numeric
    # characters and some punctuation. This routine will use a combination of of techniques including formatting and
    # concatenation. The result is an expression that can either be passed to a function or assigned to a variable.
    #
    # @param [String] string The string value to obfuscate.
    # @param [Float] threshold A floating point value between 0 and 1 that controls how much of the string is
    #   obfuscated. Higher values result in more obfuscation while 0 returns the original string without any
    #   obfuscation.
    # @return [String] An obfuscated Powershell expression that evaluates to the specified string.
    def self.scate_string_literal(string, threshold: 0.15)
      # this hasn't been thoroughly tested for strings that contain alot of punctuation, just simple ones like
      # 'AmsiUtils'
      raise ArgumentError.new('string may only contain a-z,A-Z0-9,.') if string =~ /[^a-zA-Z0-9\.,]/
      raise ArgumentError.new('threshold must be between 0 and 1') unless threshold.between?(0, 1)

      new = original = string
      occurrences = {}
      original.each_char { |char|
        occurrences[char] = 0 unless occurrences.key?(char)
        occurrences[char] += 1
      }
      char_map = occurrences.group_by { |k,v| v }.sort_by { |k,v| -k }.map { |k,v| v.shuffle }.flatten(1)

      # phase 1
      format = []
      char_subs = 0.0
      while (char_subs / original.length.to_f) < threshold
        sub_char, count = char_map.pop
        new = new.gsub(sub_char, "{#{char_subs.to_i}}")
        format << "'#{sub_char}'"
        char_subs += count
      end

      # phase 2
      concat = "'+'"
      positions = threshold > 0 ? (0..new.length).to_a.shuffle[0..(new.length * threshold)] : []
      positions.sort!
      positions.each_with_index do |position, index|
        new = new.insert(position + (index * concat.length), concat)
      end

      new = "'#{new}'"
      new = "(#{new})" unless threshold == 0

      final = new
      final << "-f#{format.join(',')}" unless format.empty?
      final = "(#{final})" unless format.empty? && threshold == 0
      final
    end

    #
    # Remove comments
    #
    # @return [String] code without comments
    def strip_comments
      # Multi line
      code.gsub!(MULTI_LINE_COMMENTS_REGEX, '')
      # Single line
      code.gsub!(SINGLE_LINE_COMMENTS_REGEX, '')

      code
    end

    #
    # Remove empty lines
    #
    # @return [String] code without empty lines
    def strip_empty_lines
      # Windows EOL
      code.gsub!(WINDOWS_EOL_REGEX, "\r\n")
      # UNIX EOL
      code.gsub!(UNIX_EOL_REGEX, "\n")

      code
    end

    #
    # Remove whitespace
    # This can break some codes using inline .NET
    #
    # @return [String] code with whitespace stripped
    def strip_whitespace
      code.gsub!(WHITESPACE_REGEX, ' ')
      code.strip!

      code
    end

    #
    # Identify variables and replace them
    #
    # @return [String] code with variable names replaced with unique values
    def sub_vars
      # Get list of variables, remove reserved
      get_var_names.each do |var, _sub|
        code.gsub!(var, "$#{@rig.init_var(var)}")
      end

      code
    end

    #
    # Identify function names and replace them
    #
    # @return [String] code with function names replaced with unique
    #   values
    def sub_funcs
      # Find out function names, make map
      get_func_names.each do |var, _sub|
        code.gsub!(var, @rig.init_var(var))
      end

      code
    end

    #
    # Perform standard substitutions
    #
    # @return [String] code with standard substitution methods applied
    def standard_subs(subs = %w(strip_comments strip_whitespace sub_funcs sub_vars))
      # Save us the trouble of breaking injected .NET and such
      subs.delete('strip_whitespace') unless get_string_literals.empty?
      # Run selected modifiers
      subs.each do |modifier|
        send(modifier)
      end
      code.gsub!(EMPTY_LINE_REGEX, '')

      code
    end
  end # Obfu
end
end
