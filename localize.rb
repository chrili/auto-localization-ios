require "pathname"

class Translation
  attr_reader :key, :val, :comment
  SUGGESTION_SEP = ";"

  def initialize key, val, comment
    @key = key
    @val = val
    @comment = comment.split(SUGGESTION_SEP)[0]
  end

  def to_s
    "/* #{comment_with_suggestions} */" + "\n" +
    "\"#{@key}\" = \"#{@val}\";"
  end

  def comment_with_suggestions
    if @suggestions
      return "#{@comment}#{SUGGESTION_SEP} Suggestions: #{@suggestions}"
    else
      return @comment
    end
  end

  # Update only the comment, not the val
  def update_with_prior_translation other
    if @key != other.key
      raise "Refuse to update non-equal translations"
    end

    @val = other.val
  end

  def add_suggested_translations suggestions
    @suggestions = suggestions
  end
end

class StringsFile
  def initialize filename
    @filename = filename
  end

  def get_translations
    regex = /\/\* (.*) \*\/\n"(.*)" = "(.*)";/

    File.open(@filename, "r") do |f|
      contents = f.read
      return contents.scan(regex).map do |matches|
        Translation.new matches[1], matches[2], matches[0]
      end
    end
  end

  def write_translations translations
    # Output to disk, overwriting old strings
    data = translations.map{|t| t.to_s}.join("\n\n")
    File.open(@filename, "w") do |f|
      f.write(data)
    end
  end
end

class TranslationMerger
  def initialize oldTranslations, newTranslations
    @oldTranslations = oldTranslations
    @newTranslations = newTranslations
  end

  def get_merged_sorted_translations
    get_merged_translations.sort_by(&:key)
  end

  def get_merged_translations
    # Merge, replacing new values with old values which are already translated
    uniqueTranslations = {}

    @newTranslations.each {|t| uniqueTranslations[t.key] = t}

    @oldTranslations.each do |t|
      if uniqueTranslations[t.key] != nil
        uniqueTranslations[t.key].update_with_prior_translation t
      else
        uniqueTranslations[t.key] = t
      end
    end

    uniqueTranslations.values
  end
end

# Adds suggested translations to the comment
class Translator
  def initialize translations, language
    @translations = translations
    @language = language
  end

  def translations_with_suggestions
    IO.popen("./translation_helper.swift #{@language}", "r+") do |io|
      io.write translation_input
      io.close_write
      result = io.read

      pairs = result.split("\n").map do |line|
        line.split("\t")
      end
      lookup = Hash[*pairs.flatten]

      # Add translations to existing
      @translations.each do |t|
        t.add_suggested_translations lookup[t.key]
      end
    end

  end

  def translation_input
    @translations.map do |t|
      t.key
    end.join("\n")
  end
end

CODE_DIR = Pathname.new ARGV[0]
LPROJ_DIR = Pathname.new ARGV[1]
TMP_DIR = LPROJ_DIR + "tmp"
STRINGS_FILE = LPROJ_DIR + "Localizable.strings"

language = LPROJ_DIR.basename.to_s.split(".")[0]
STDERR.puts "Inferred language: #{language}"

# Generate new strings
TMP_DIR.mkdir unless TMP_DIR.exist?
`genstrings #{CODE_DIR}/*.m -o #{TMP_DIR}`
`iconv -f UTF-16 -t UTF-8 #{TMP_DIR + "Localizable.strings"} > #{TMP_DIR + "Localizable.strings.utf8"}`

# Read old strings into memory
oldStringsFile = StringsFile.new(STRINGS_FILE)
oldTranslations = oldStringsFile.get_translations
STDERR.puts "Got #{oldTranslations.length} existing translations"

# Read new strings into memory
newStringsFile = StringsFile.new(TMP_DIR + "Localizable.strings.utf8")
newTranslations = newStringsFile.get_translations
STDERR.puts "Got #{newTranslations.length} new translations"

# Merge
mergedTranslations = TranslationMerger.new(oldTranslations, newTranslations).get_merged_sorted_translations
STDERR.puts "Merged set has #{mergedTranslations.length} entries"

# Add suggestions
translationsWithSuggestions = Translator.new(mergedTranslations, language).translations_with_suggestions

# Write to disk
oldStringsFile.write_translations translationsWithSuggestions
STDERR.puts "Wrote to disk"

# Cleanup
TMP_DIR.rmtree