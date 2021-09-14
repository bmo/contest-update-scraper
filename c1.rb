require 'rubygems'
require 'nokogiri'
require 'open-uri'

#
# TODO make dates print correctly
# TODO write summary, details, and logs due to same or separate files.


class ContestPeriod
  class DateParseError < StandardError; end

  attr_accessor :original_period, :start_time, :end_time, :extra_info, :is_local, :year

  MONTHS = "jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec"
  MONTHS_ARY = MONTHS.split(/\|/)
  MONTH_REGEX =  /(#{MONTHS})/
  TIME_RANGE_FORMAT = /(\d{4})[zZ]\-(\d{4})[zZ]/
  FORMAT_AND_1 = /((\d{4})[zZ]\-(\d{4})[zZ]\s+and)+/mi
  #FORMAT_AND_ALL = /(#{FORMAT_AND_1}+)\s+#{TIME_RANGE_FORMAT},\s+#{MONTH_REGEX}+(\d{1,2})(.*)/i
  FORMAT_END = /(\d{4})[zZ]\-(\d{4})[zZ],\s+#{MONTH_REGEX}\s+(\d{1,2})/i

  FORMAT1 = /^\W*\s*(\d{4})[zZ]\-(\d{4})[zZ],\s+#{MONTH_REGEX}\s+(\d{1,2})(,\s+(\d{4}))*(.*)/i  # 0200z-0300z, Jul 10
  FORMAT2 = /^\W*\s*(\d{4})[zZ],\s+#{MONTH_REGEX}\s+(\d{1,2})\s+to\s+(\d{4})[zZ],\s+#{MONTH_REGEX}\s+(\d{1,2})(.*)/i  #1500Z, Jul 4 to 1500Z, Jul 5
  #
  FORMAT3 = /^\W*\s*(\d{4})\s+local,\s+#{MONTH_REGEX}\s+(\d{1,2})\s+to\s+(\d{4})\s+local,\s+#{MONTH_REGEX}\s+(\d{1,2})(.*)/i #2000 local, Jul 4 to 0200 local, Jul 5

  #  1900 local-2300 local, Sep 21
  # 1900 local - 2300 local, sep 29]
  FORMAT4 = /^\W*\s*(\d{4})\s+local\s*-\s*(\d{4})\s+local,\s+#{MONTH_REGEX}\s+(\d{1,2})(.*)/i

  #   1500-1700Z, Nov 15 (80m)
  FORMAT5 = /^\W*\s*(\d{4})\s*[zZ]?\s*-\s*(\d{4})\s*[zZ],\s+#{MONTH_REGEX}\s+(\d{1,2})(.*)/i
  #   [1300-1500Z, Nov 15 (40m)]

  FORMAT6 =  /^\W*\s*(\d{4})\s*[zZ]?\s*-\s*(\d{4})\s*([zZ]|local)?,\s+#{MONTH_REGEX}\s+(\d{1,2})(.*)/i  #[0800-1400 local, May 7]

  # 0600Z Aug 27 to 0559Z, Aug 28
  FORMAT7 = /^\W*\s*(\d{4})[zZ]\s+#{MONTH_REGEX}\s+(\d{1,2})\s+to\s+(\d{4})[zZ][,]?\s++#{MONTH_REGEX}\s+(\d{1,2})(.*)/i  # 0200z-0300z, Jul 10

  # "0800-1800 local, Apr 22"
  FORMAT8 = /^\W*\s*(\d{4})\s*-\s*(\d{4})\s+local,\s+#{MONTH_REGEX}\s+(\d{1,2})(.*)/i

  #   1400Z to 2400Z, Oct 14
  FORMAT9 = /^\W*\s*(\d{4})\s*[zZ]?\s*to\s*(\d{4})\s*[zZ],\s+#{MONTH_REGEX}\s+(\d{1,2})(.*)/i

  # "Feb 22, 2022"
  FORMAT10 =/#{MONTH_REGEX}\s+(\d{1,2}),\s+(20\d\d)/i
  
  def initialize(string_to_parse, year)
    puts "ContestPeriod: <<< #{string_to_parse} >>> YEAR #{year}"
    string_to_parse = string_to_parse.gsub("june","jun")
    self.original_period = string_to_parse
    self.year = year.to_i
    # handle 0000z-2400z, Jul 10 (CW)
    # 0000Z, Jul 4 to 2359Z, Jul 5
    # "1400Z, June 2 to 0200Z, Jun 3"

    interpret_time(self.original_period)
  end

  def month_number_for_word(word)
    month_number = MONTHS_ARY.index(word.downcase)

    if month_number.nil?
      return nil
    end

    month_number += 1
  end

  # adjust the year for the contest month value
  # if year is Nov or Dec, and month is 0 - 4, use next year
  def adjusted_year_for_month(contest_month)
    now_month_index = Time.now.month - 1
    contest_month_index = MONTHS_ARY.find_index(contest_month.downcase)
    if contest_month_index < 0
      raise Exception.new("Month #{contest_month} not valid!")
    end
    adjusted_year = self.year
    if now_month_index >= 10 && (contest_month_index.between?(0, 9)) #
      adjusted_year = adjusted_year # + 1
    end
    adjusted_year
  end

  def interpret_time(time_specifier)
    time_specifier.downcase!
    lwr_date = time_specifier.gsub("june", "jun")
    self.is_local = false
    # handle conjunctions
    # 0900Z-1200Z and 1300Z-1600Z, Jul 19

    # 2000Z-2159Z, Jul 12
    if (m = FORMAT1.match(lwr_date))
      #  1:"0230" 2:"0300" 3:"Jul" 4:"3" 5:nil 6:nil>
      start_hm = m[1]
      end_hm = m[2]
      start_month = m[3]
      end_month = m[3]
      start_day = m[4]
      end_day = m[4]

      self.extra_info = m[7]

    elsif (m = FORMAT2.match(lwr_date)) || (m = FORMAT3.match(lwr_date))
      #<MatchData "0800Z, Oct 1 to 2000Z, Oct 7" 1:"0800" 2:"Oct" 3:"1" 4:"2000" 5:"Oct" 6:"7" 7:"">
      self.is_local = !(FORMAT3.match(lwr_date).nil?)   # if it matched it's local time
      # #<MatchData "1500Z, Jul 4 to 1500Z, Jul 5" 1:"1500" 2:"Jul" 3:"4" 4:"1500" 5:"Jul" 6:"5">
      start_hm = m[1]
      end_hm = m[4]
      start_month = m[2]
      end_month = m[5]
      start_day = m[3]
      end_day = m[6]
      self.extra_info = m[7]
      #puts m.inspect
    elsif (m = FORMAT8.match(lwr_date))
      self.is_local = true
      start_hm = m[1]
      end_hm = m[2]
      start_month = m[3]
      end_month = m[3]
      start_day = m[4]
      end_day = m[4]
      self.extra_info = m[5]
    elsif (m = FORMAT9.match(lwr_date))
      self.is_local = true
      start_hm = m[1]
      end_hm = m[2]
      start_month = m[3]
      end_month = m[3]
      start_day = m[4]
      end_day = m[4]
      self.extra_info = m[5]
    elsif (m = FORMAT4.match(lwr_date)) || (m = FORMAT5.match(lwr_date))
      # #<MatchData "1900 local - 2300 local, sep 29" 1:"1900" 2:"2300" 3:"sep" 4:"29">
      start_hm = m[1]
      end_hm = m[2]
      start_month = m[3]
      end_month = m[3]
      start_day = m[4]
      end_day = m[4]
      self.extra_info = m[5]
    elsif (m = FORMAT6.match(lwr_date))
      # #<MatchData "1900 local - 2300 local, sep 29" 1:"1900" 2:"2300" 3:"sep" 4:"29">
      start_hm = m[1]
      end_hm = m[2]
      start_month = m[3]
      end_month = m[4]
      start_day = m[5]
      end_day = m[5]
      self.extra_info = m[6]
    elsif (m = FORMAT7.match(lwr_date))
      #<MatchData "0600Z Aug 27 to 0559Z, Aug 28" 1:"0600" 2:"Aug" 3:"27" 4:"0559" 5:"Aug" 6:"28" 7:"">
      start_hm = m[1]
      end_hm = m[4]
      start_month = m[2]
      end_month = m[5]
      start_day = m[3]
      end_day =  m[6]
      self.extra_info = m[7]                  
    elsif lwr_date.match(/cancelled/)
      # handle cancelled contests.
      start_hm = "0000"
      end_hm = "0000"
      start_month = "Jan"
      end_month = "Jan"
      start_day = "1"
      end_day = "1"
    else
      # Cannot parse it
      puts "\n\nCannot parse ""#{lwr_date}""\n\n"
      raise DateParseError.new("Cannot Parse [#{lwr_date}]")
      return
    end

    start_month_number = month_number_for_word(start_month)
    end_month_number = month_number_for_word(end_month)

    if start_month_number.nil? || end_month_number.nil?
      puts "Invalid month"
      return
    end

    start_year = self.year # adjusted_year_for_month(start_month)
    end_year = self.year + (end_month_number < start_month_number ? 1 : 0) #adjusted_year_for_month(end_month)

    # make into this format 1985-04-12T23:20:50.52Z to parse with RFC3339 format
    #                       2015-04-07T::00.00Z
    #puts "Start hm #{start_hm}"
    ds_start = "#{start_year}-#{start_month_number.to_s.rjust(2, '0')}-#{start_day.rjust(2, '0')}T#{start_hm[0, 2]}:#{start_hm[2, 2]}:00Z"
    ds_end = "#{end_year}-#{end_month_number.to_s.rjust(2, '0')}-#{end_day.rjust(2, '0')}T#{end_hm[0, 2]}:#{end_hm[2, 2]}:00Z"


    puts ("time: #{lwr_date} -> start #{ds_start} end #{ds_end}")
    self.start_time = DateTime.rfc3339(ds_start)
    self.end_time = DateTime.rfc3339(ds_end)
  end

  def start_in_period(start_time, end_time)
    if self.start_time.nil?
      puts "Start time is nil!!!! original period #{self.original_period}"
      #puts self.inspect
    end
    (DateTime.parse(start_time) <= self.start_time) && (self.start_time <= DateTime.parse(end_time))
  end

  def contest_time_format(t_date_time)
    t_date_time.strftime("%b %-d, %H%M#{self.is_local ? " (local)" : "z"}")
  end

  def to_contest_format
    # print it in the contest format
    "#{contest_time_format(self.start_time)} to #{contest_time_format(self.end_time)}#{self.extra_info}"
  end


  # 1300Z-1400Z, Jul 15 and 1900Z-2000Z, Jul 15 and 0300Z-0400Z, Jul 16, 2015
  # 1700Z-1800Z, Jun 4 (CW) and 1800Z-1900Z, Jun 4 (SSB) and  1900Z-2000Z, Jun 4 (FM) and  2000Z-2100Z, Jun 4 (Dig)
  # handle the string, return one or more ContestPeriods
  def self.interpret_original_period(o_string, year)
    puts("interpret_original_period \"#{o_string}\" #{year}")
    new_string = o_string
    # [0900Z-1200Z and 1300Z-1600Z, Jul 19]
    #matched_times =  o_string.scan(/(#{TIME_RANGE_FORMAT}+\s+and)/)
    matched_times = o_string.scan(FORMAT_AND_1)
    matched_end = o_string.match(FORMAT_END)
    puts("matched times #{matched_times.inspect} matched end #{matched_end.inspect}")
    if (matched_times && !matched_times.empty?) && matched_end
      accumulated_periods = []
      # handle month and day
      month = matched_end[3]
      day = matched_end[4]
      puts "MATCHED TIMES #{matched_times.inspect}"
      matched_times.each do |m|
        # ["0900Z-1200Z and", "0900", "1200"]
        single_date = "#{m[1]}Z-#{m[2]}Z, #{month} #{day}"
        accumulated_periods << self.new(single_date, year)
        o_string.sub!(m[0],"")
      end
      accumulated_periods << self.new(o_string, year)
    else
      return([self.new(o_string, year)])
    end
  end

end

class ContestItemParser
  attr_reader :doc, :dates, :logs_due, :contest_periods
  attr_accessor :times, :year

  def initialize(link, year, times)
     # puts "ContentItemParser with #{link}"
     @doc =  Nokogiri::HTML(open(link))
     self.year = year
     self.times= times
  end

  def file=(name)
    contents = nil
    File.open(name){ |f|
      contents = f.readlines();
    }
    @doc = Nokogiri::HTML(contents)
  end
                                            
  def contest_name
    @doc.css("div#main td")[0].text
  end

  def modes
    @doc.css("div#main td:contains('Mode:') ~ td").text
  end

  def bands
    @doc.css("div#main td:contains('Bands:') ~ td").text
  end

  def is_vhf_uhf?
    !bands.scan(/50|70|144|432|1296/).empty? || !bands.scan(/2m|6m|70cm|23cm/).empty? || bands.downcase.match(/uhf|vhf/)
  end

  def is_hf?
    !bands.scan(/160|80|40|20|15|10/).empty?
  end

  def exchange
    @doc.css("div#main td:contains('Exchange:') ~ td").children.select(&:text?).join(", ")
  end

  def rules_link
    @doc.css("div#main td:contains('Find rules at:') ~ td").text
  end

  # some weekly contests have logs due before the contest start.
  def fix_weekly_log_due_time
    old_logs_due = @logs_due
    while @logs_due < self.contest_periods.last.end_time do
      @logs_due += 7
    end

    if old_logs_due != @logs_due
      puts "Fixed weekly log due date for #{contest_name}: #{old_logs_due} -> #{@logs_due}"
    end
  end

  # handle contests with log due dates in a year AFTER the contest date
  def logs_due_next_year?(log_due)
    contest_month = self.contest_periods.last.end_time.month
    (log_due.month < contest_month) && (log_due < self.contest_periods.last.end_time)
  end

  def logs_due_fixed
    logs_due_s = logs_due_value
    return logs_due_s if logs_due_s == "see rules"
    the_day = DateTime.parse(logs_due_s)

    if logs_due_next_year?(the_day)
      the_day = the_day.next_year
      puts "Fixed next-year's log due date for #{contest_name}: to #{the_day.year}"
    end

    @logs_due ||= DateTime.new(the_day.year, the_day.month, the_day.day, 23, 59, 59)

    #puts("LOGS DUE #{@logs_due}")
    fix_weekly_log_due_time

    @logs_due.strftime("%B %-d")
  end

  def logs_due_value
    first_logs_due_value
    lds_el = @doc.css("div#main td:contains('Logs due:')").first
    return "see rules" unless lds_el&.previous_sibling
    td_before = lds_el.previous_sibling
    puts "LOGSDUEVALUE"
    puts lds_el.text
    puts "Previous #{td_before.text}"
    lds = lds_el && lds_el.text.gsub(/^.*Logs due:\s*\d{4}Z,\s*/, "")
    puts lds.gsub(/\W*\d{4}Z\-\d{4}Z,\s*/, "")
    (lds && Date.strptime(lds.gsub(/\W*\d{4}Z\-\d{4}Z,\s*/, ""), '%b %d').strftime("%B %-d")) || "see rules"
  end

  def first_logs_due_value
    future_dates = @doc.css("div#main td:contains('Future Dates')").first
    first_due_tr = future_dates.parent
    contents_tr = first_due_tr.next
    puts "contents_tr #{contents_tr.inspect}"
    first_due_td_0 = contents_tr.css('td')[1]
    first_due_td_1 = contents_tr.css("td:contains('Logs due:')").first
    puts "first_due 0 #{first_due_td_0}"
    puts "first_due 1 #{first_due_td_1}"

    lds = first_due_td_1  && first_due_td_1.text.gsub(/^.*Logs due:\s*\d{4}Z,\s*/, "") # "  Logs due: 0000Z, Mar 1" -> "Mar 1"
    dt = nil
    if lds && (m=first_due_td_0.text.downcase.match(ContestPeriod::FORMAT10))
       year = m[3] || Time.zone.now.strftime("%Y")
       puts "STRPTIME of \"#{lds}, #{year}\""
       dt = Date.strptime("#{lds}, #{year}","%b %d, %Y")
    end
    (dt && dt.strftime("%B %-d")) || "see rules"
  end

  def repair_multiple_segments(original_times)
    times = original_times.dup
    if times.length < 2
      return times
    end

    (0..times.length-1).each do |i|
      if !times[i].nil? && !times[i].downcase.strip.match(/#{ContestPeriod::MONTH_REGEX}/i)
        puts "fixing #{i} [#{times[i]}] of #{times.length} from #{times.inspect}"
        times[i] = times[i] + times[i+1] if times[i+1]
        times[i+1] = nil
      end
    end
    times.compact
  end

  def times=(the_time)
    @contest_periods = []
    @times = the_time
    # handle this case  ["0500Z-0800Z and", "  1500Z-1800Z, Dec 1 and", "  0700Z-1000Z, Dec 2"]
    the_time = repair_multiple_segments(the_time)

    @contest_periods = the_time.map{|tv|
      #ContestPeriod.new(tv)
      #puts "times= Tv is #{tv}"
      ContestPeriod.interpret_original_period(tv.gsub("June","Jun").downcase, self.year)
    }

    @contest_periods.flatten!

    @dates = @times.map{|tv|
      # 0000z-2400z, Jul 10 (CW)
      # Date.strptime('jul 16 (CW)', '%b %d')
      #
      # could also be 0000Z, Jul 4 to 2359Z, Jul 5
      begin
        Date.strptime(tv.gsub(/\W*\d{4}Z\-\d{4}Z,\s*/,""), '%b %d')
      rescue ArgumentError
        []
      end
    }
  end

end

class ContestFragmentParser
  attr_reader :by_date
  attr_accessor :start_date
  attr_accessor :end_date

  CONTEST_URL_ROOT = 'https://www.contestcalendar.com'
  MONTH_NAMES = "january|february|march|april|may|june|july|august|september|october|november|december"
  #MONTH_NAMES_ARY = MONTH_NAMES.split(/\|/)
  MONTH_NAMES_REGEX =  "(#{MONTH_NAMES})"

  def initialize(filename)
    if filename.nil?
      filename = "#{CONTEST_URL_ROOT}/contestcal.html"
    end

    if filename.downcase.match(/^http/)
      puts "Opening (HTML) #{filename}"
      @doc = Nokogiri::HTML(open(filename))
      @page_url = filename
    else
      puts "Opening #{filename}"
      @doc = Nokogiri::HTML(File.read(filename))
    end

  end


  def contest_links
    @doc.css("tr")
  end

  def link(el)
    the_el = el.css("a").first
    the_el && the_el[:href]
  end

  def is_date(el)
    # match "January 2020" in text part
    m = el.text.downcase.match(/(#{MONTH_NAMES_REGEX})\s+(\d{4})/)
    return nil if m.nil?
    return m[2], m[3]
  end

  def times(el)
    el.css("td")[1].children.select(&:text?).map{|l| l.text.gsub(/\s* and\s*$/,"")}
  end

  def raw_times(el)
    el.css("td")[1].children.select(&:text?).map{|l| l.text}
  end

  def get_info
    link_month = nil
    link_year = nil
    @contests = []
    contest_links.each{|l|
      # Handle each individual link on the page, which is interspersed with the dates.
      #puts "CONTEST LINK #{l}"
      m, y = is_date(l)
      if m && y
        link_month = m
        link_year = y
        puts "FOUND A DATE! #{m} #{y}"
        next
      end

      the_link = link(l)
      next if the_link.nil?

      if @page_url
        the_link = URI.join(@page_url,the_link).to_s
      end

      #puts("Link ((#{l}))")
      some_times = raw_times(l)

      puts("\nParsing link: link #{the_link} year #{link_year} some_times #{some_times}")
      begin
        ci = ContestItemParser.new(the_link, link_year, some_times)
        @contests << ci
      rescue ContestPeriod::DateParseError => ex
        "Cannot Parse Date for #{the_link}"
      end

    }
    date_order
  end

  def date_order
    @by_date = {}
    @contests.each{|c|
      puts "contest #{c.contest_name} #{ c.contest_periods.inspect }"
      c.contest_periods.each{|cp|
        if cp.start_time
          h = cp.start_time.strftime("%B %-d")
          puts "Adding to day #{h}"
          @by_date[h] ||= []
          @by_date[h] << c
        else

        end
      }
    }
  end

  def contests
    @contests
  end

  def section_with_criteria(doc, section_title=nil)
    already_shown = []
    (Date.parse(self.start_date)..Date.parse(self.end_date)).each { |date|
      #doc.ul {
      date_key = date.strftime("%B %-d")
      puts "looking for #{date_key} #{@by_date[date_key] && @by_date[date_key].length}"

      if (section_title)
        doc.span {
          doc.text(section_title)
        }
      end

      if @by_date[date_key]
        @by_date[date_key].each { |contest|
          if !already_shown.include?(contest.hash) && (!block_given? || yield(contest))
            doc.span {
              puts contest.hash
              doc.a(:href => contest.rules_link) {
                doc.text(contest.contest_name)
              }
              doc.text(", ")
              doc.text(
                  contest.contest_periods.map { |cp|
                    cp.to_contest_format
                  }.join(", ")
              )
              doc.text("; ")
              doc.text(contest.modes)
              doc.text("; Bands: ")
               bands_for_print(doc, contest.bands)
              doc.text("; ")
              doc.text(contest.exchange)
              doc.text("; Logs due: ")
              doc.text(contest.logs_due_fixed)
              doc.text(".")
            }
            doc.br()
            already_shown << contest.hash
          end
        }
        #}
      end
    }
  end

  def contest_details_for_period
    builder = Nokogiri::HTML::Builder.new do |doc|
      doc.html {
        doc.body() {
          #puts "#{@by_date.keys.inspect}"

          section_with_criteria(doc)
          section_with_criteria(doc,"UHF/VHF"){|c| c.is_uhf_vhf?}
        }
      }
    end
  end

  def contest_summary
    builder = Nokogiri::HTML::Builder.new do |doc|
      doc.html {
        doc.body() {
          puts "#{@by_date.keys.inspect}"
          (DateTime.parse(self.start_date)..DateTime.parse(self.end_date)).each { |date|
            #doc.ul {
            date_key = date.strftime("%B %-d")
            puts "looking for #{date_key} #{@by_date[date_key] && @by_date[date_key].length}"

            if @by_date[date_key]
              #    doc.li {
              doc.b {
                doc.text(date_key)
              }
              #    }
              doc.ul {
                @by_date[date_key].each { |contest|
                  doc.li {
                    doc.a(:href => contest.rules_link) {
                      if is_arrl_contest?(contest.contest_name)
                        doc.b {
                          doc.text(contest.contest_name)
                        }
                      else
                        doc.text(contest.contest_name)
                      end
                    }
                  }
                }
              }
            end
            #}
          }
        }
      }
    end
    #
    # (Date.parse("July 2, 2015")..Date.parse("July 15, 2015")).each { |date| puts date; goo.by_date[date].each{|c| puts "#{c.contest_name} #{c.rules_link}" } if goo.by_date[date] }
  end

  def logs_due
    nnc = self.contests.select{|c| c.logs_due }.compact
    sorted_by_date = nnc.sort_by { |c| c.logs_due }

    builder = Nokogiri::HTML::Builder.new do |doc|
      doc.html {
        doc.body() {
          start_date = DateTime.parse(@start_date)
          end_date = DateTime.parse(@end_date)
          old_due_date = nil
          sorted_by_date.each { |c|
            next if c.logs_due.nil?
            puts("Logs Due #{c.logs_due.inspect} #{start_date} #{end_date}")
            next if (c.logs_due < start_date) || (c.logs_due > end_date)

            if old_due_date != c.logs_due
              #doc.br()
              doc.b {
                doc.text(c.logs_due.strftime("%B %-d, %Y"))
              }
              old_due_date = c.logs_due
            end
            doc.ul {
              doc.li {
                doc.a(:href => c.rules_link) {
                  if is_arrl_contest?(c.contest_name)
                    doc.b {
                      doc.text(c.contest_name)
                    }
                  else
                    doc.text(c.contest_name)
                  end
                }
              }
            }

          }
        }
      }
    end
  end

  ARRL_CONTEST_REGEX = /^ARRL|North American Sprint|North American QSO|IARU HF World Championship/

  def is_arrl_contest?(contest_name)
    contest_name.match(ARRL_CONTEST_REGEX)
  end

  def highlight_vhf(bands)
    text = bands
    bands.gsub("6m")
  end

  def bands_for_print(doc,bands)
    bands = bands.strip
    if bands == ""
      doc.text("(see rules)")
      return
    end
    doc.text(bands)
  end

  def contest_details
    #
    #CWops Mini-CWT Test, June 18 0300z-0400z, June 24 1300Z-1400Z,  June 24 1900Z-2000Z,  June 25 0300Z-0400Z, July 1 1300Z-1400Z, July 1 1900Z-2000Z;
    # CW; Bands: 1.8-28MHz;Member: Name + Member No., non-Member: Name + (state/province/country); Logs Due: June 20, June 27, July 4, 2015.
    #
    builder = Nokogiri::HTML::Builder.new do |doc|
      doc.html {
        doc.body {
          @contests.each { |contest|
            #puts "CONTEST #{contest.inspect}"
            next unless contest.contest_periods.any?{|cp| cp.start_in_period(self.start_date, self.end_date) }

            #contest.fix_log_due_time

            doc.span {
              doc.a(:href => contest.rules_link) {
                if is_arrl_contest?(contest.contest_name)
                  doc.b { doc.text(contest.contest_name) }
                else
                  doc.text(contest.contest_name)
                end
              }
              doc.text( ", " )
              doc.text(
                contest.contest_periods.map { |cp|
                  cp.to_contest_format
                }.join(", ")
              )
              doc.text( "; ")
              doc.text( contest.modes )
              doc.text( "; Bands: ")
              bands_for_print(doc, contest.bands)
              doc.text( "; " )
              doc.text(contest.exchange)
              doc.text("; Logs due: ")
              doc.text(contest.logs_due_fixed)
              doc.text(".")

            }
            doc.br();
            doc.br();
          }
        }
      }
    end
  end


  # how to use
  # go to the wa7bnm 12 month page, save as "web page complete" in Chrome. This gets the normalized URLs with domain, etc.
  #
  # goo = ContestFragmentParser.new(html_fragment_to_parse)
  # goo.start_date = "July 1, 2015"; goo.end_date = "July 15, 2015"
  # goo.get_info
  # y = goo.contest_details
  # y.to_html
  # y.contest_summary                   

end

class ContestReport
  def self.date_of_next(day)
    date  = Date.parse(day)
    delta = date > Date.today ? 0 : 7
    date + delta
  end

  def self.run!(start_date_s=nil, end_date_s=nil, input_file=nil, output_file_root=nil)
    if start_date_s.nil?
      #
      start_date = self.date_of_next("Thursday").to_s
    else
      start_date = DateTime.parse(start_date_s).to_s
    end

    if output_file_root.nil?
      output_file_root = "/tmp/cr_#{DateTime.parse(start_date).strftime('%F')}"
    end

    if end_date_s.nil?
      end_date = (DateTime.parse(start_date) + 13 + Rational(86399, 86400) ).to_s
    else
      end_date = DateTime.parse(end_date_s).to_s
    end
    puts "Start Date is #{start_date}"
    puts "End Date is   #{end_date}"
    cfd = ContestFragmentParser.new(input_file)
    cfd.start_date = start_date
    cfd.end_date = end_date

    cfd.get_info
    cd = cfd.contest_details
    output_file_details = "#{output_file_root}_details.html"
    output_file_summary = "#{output_file_root}_summary.html"
    output_file_logs_due = "#{output_file_root}_logs_due.html"
    output_file_logs_due_1 = "#{output_file_root}_logs_due_1.html"


    File.open(output_file_details, "w"){ |f| f.write(cd.to_html)}
    File.open(output_file_logs_due_1, "w") { |f| f.write(cfd.logs_due.to_html) }
    File.open(output_file_summary, "w"){ |f| f.write(cfd.contest_summary.to_html)}

    #
    File.open(output_file_logs_due, "w"){ |f| f.write(ContestLogsDueParser.new(start_date, end_date).logs_due.to_html)}
    
  end
end

class ContestLogsDueParser
  attr_accessor :doc

  CONTEST_URL_ROOT = 'https://www.contestcalendar.com'

  def initialize(start_date=nil, end_date=nil)
    @start_date = DateTime.parse(start_date) if start_date
    @end_date = DateTime.parse(end_date) if end_date
    @link = "#{CONTEST_URL_ROOT}/duedates.php"
    @doc = Nokogiri::HTML(open(@link))
    @all_dates = @doc.css("div#main tr td[class=bgray]:first-child")
  end

  def logs_due
    builder = Nokogiri::HTML::Builder.new do |doc|
      doc.html {
        doc.body() {
          old_due_date = nil
          @all_dates.each { |el|
            el2 = el.next_sibling
            name = el2.text
            tr = el.parent.next_sibling
            while (tr && !@all_dates.include?(tr)) do
              if (!tr.css("td span:contains('Find rules at:')").empty?)
                break
              end
              tr = tr.next_sibling
            end
            if (tr) then
              rules_link = tr.css("td span:contains('Find rules at:')").first.parent.next.text
            end
            due_date = el.text

            # skip if not in our date range
            next if ((!@start_date.nil? && DateTime.parse(due_date) < @start_date) || (!@end_date.nil? && DateTime.parse(due_date) > @end_date))

            if old_due_date != due_date
              #doc.br()
              doc.b {
                doc.text(due_date)
              }
              old_due_date = due_date
            end
            doc.ul {
              doc.li {
                doc.a(:href => rules_link) {
                  doc.text(name)
                }
              }
            }

          }
        }
      }
    end
  end
  #  el1 = cd.doc.css("div#main tr td[class=bgray]:first-child").first - the date part
  # el2 = el1.next_sibling  # the name of the contest
  # el2.parent.parent.css("td span:contains('Find rules at:')").first.parent.next
  # el2 =  parel.next.next.next.next.next.next.next.next
  # el2.css("td span:contains('Find rules at:')").first.parent.next
end
puts "you probably want ContestReport.run!"
#ContestReport.run!("2017-11-16")