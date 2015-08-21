require 'rubygems'
require 'nokogiri'
require 'open-uri'

#
# TODO make dates print correctly
# TODO write summary, details, and logs due to same or separate files.


class ContestPeriod
  attr_accessor :original_period, :start_time, :end_time, :extra_info, :is_local

  MONTHS = "jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec"
  MONTHS_ARY = MONTHS.split(/\|/)
  MONTH_REGEX =  "(#{MONTHS})"
  TIME_RANGE_FORMAT = /(\d{4})[zZ]\-(\d{4})[zZ]/
  FORMAT_AND_1 = /((\d{4})[zZ]\-(\d{4})[zZ]\s+and)+/mi
  #FORMAT_AND_ALL = /(#{FORMAT_AND_1}+)\s+#{TIME_RANGE_FORMAT},\s+#{MONTH_REGEX}+(\d{1,2})(.*)/i
  FORMAT_END = /(\d{4})[zZ]\-(\d{4})[zZ],\s+#{MONTH_REGEX}\s+(\d{1,2})/i
  FORMAT1 = /^\W*\s*(\d{4})[zZ]\-(\d{4})[zZ],\s+#{MONTH_REGEX}\s+(\d{1,2})(,\s+(\d{4}))*(.*)/i  # 0200z-0300z, Jul 10
  FORMAT2 = /^\W*\s*(\d{4})[zZ],\s+#{MONTH_REGEX}\s+(\d{1,2})\s+to\s+(\d{4})[zZ],\s+#{MONTH_REGEX}\s+(\d{1,2})(.*)/i  #1500Z, Jul 4 to 1500Z, Jul 5
  #
  FORMAT3 = /^\W*\s*(\d{4})\s+local,\s+#{MONTH_REGEX}\s+(\d{1,2})\s+to\s+(\d{4})\s+local,\s+#{MONTH_REGEX}\s+(\d{1,2})(.*)/i #2000 local, Jul 4 to 0200 local, Jul 5
  # 1900 local - 2300 local, sep 29]
  FORMAT4 = /^\W*\s*(\d{4})\s+local\s+-\s+(\d{4})\s+local,\s+#{MONTH_REGEX}\s+(\d{1,2})(.*)/i
  #
  def initialize(string_to_parse)
    self.original_period = string_to_parse
    # handle 0000z-2400z, Jul 10 (CW)
    # 0000Z, Jul 4 to 2359Z, Jul 5
    interpret_time(self.original_period)
  end

  def month_number_for_word(word)
    month_number = MONTHS_ARY.index(word.downcase)

    if month_number.nil?
      return nil
    end

    month_number += 1
  end



  def interpret_time(time_specifier)
    #
    lwr_date = time_specifier
    self.is_local = false;
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
      start_year = Time.now.year
      end_year = Time.now.year
      self.extra_info = m[7]

    elsif ((m = FORMAT2.match(lwr_date)) || (m = FORMAT3.match(lwr_date)))
      self.is_local = !(FORMAT3.match(lwr_date).nil?) # if it matched it's local time
      # #<MatchData "1500Z, Jul 4 to 1500Z, Jul 5" 1:"1500" 2:"Jul" 3:"4" 4:"1500" 5:"Jul" 6:"5">
      start_hm = m[1]
      end_hm = m[4]
      start_month = m[2]
      end_month = m[5]
      start_day = m[3]
      end_day = m[6]
      start_year = Time.now.year
      end_year = Time.now.year
      self.extra_info = m[7]
    elsif (m = FORMAT4.match(lwr_date))
      # #<MatchData "1900 local - 2300 local, sep 29" 1:"1900" 2:"2300" 3:"sep" 4:"29">
      start_hm = m[1]
      end_hm = m[2]
      start_month = m[3]
      end_month = m[3]
      start_day = m[4]
      end_day = m[4]
      start_year = Time.now.year
      end_year = Time.now.year
      self.extra_info = m[5]
    else
      # Cannot parse it
      puts "\n\nCannot parse [#{lwr_date}]\n\n"
      return
    end

    start_month_number = month_number_for_word(start_month)
    end_month_number = month_number_for_word(end_month)
    if start_month_number.nil? || end_month_number.nil?
      puts "Invalid month"
      return
    end
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
  def self.interpret_original_period(o_string)

    new_string = o_string
    # [0900Z-1200Z and 1300Z-1600Z, Jul 19]
    #matched_times =  o_string.scan(/(#{TIME_RANGE_FORMAT}+\s+and)/)
    matched_times = o_string.scan(FORMAT_AND_1)
    matched_end = o_string.match(FORMAT_END)
    if (matched_times && !matched_times.empty?) && matched_end
      accumulated_periods = []
      # handle month and day
      month = matched_end[3]
      day = matched_end[4]
      matched_times.each do |m|
        # ["0900Z-1200Z and", "0900", "1200"]
        single_date = "#{m[1]}Z-#{m[2]}Z, #{month} #{day}"
        accumulated_periods << self.new(single_date)
        o_string.sub!(m[0],"")
      end
      accumulated_periods << self.new(o_string)
    else
      return([self.new(o_string)])
    end
  end

end

class ContestItemParser
  attr_reader :doc, :dates, :contest_periods
  attr_accessor :times

  def initialize(link)
     @doc =  Nokogiri::HTML(open(link))
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

  def exchange
    @doc.css("div#main td:contains('Exchange:') ~ td").children.select(&:text?).join(", ")
  end

  def rules_link
    @doc.css("div#main td:contains('Find rules at:') ~ td").text
  end

  def logs_due
    lds_el = @doc.css("div#main td:contains('Logs due:')").first
    lds = lds_el && lds_el.text.gsub(/^.*Logs due:\s*/,"")
    (lds && Date.strptime(lds.gsub(/\W*\d{4}Z\-\d{4}Z,\s*/,""), '%b %d').strftime("%B %-d")) || "see rules"
  end

  def times=(the_time)
    @contest_periods = []
    @times = the_time
    #puts "the_time #{the_time.inspect}"
    @contest_periods = the_time.map{|tv|
       #ContestPeriod.new(tv)
      ContestPeriod.interpret_original_period(tv)
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

  def initialize(filename)
    if filename.downcase.match(/^http/)
      @doc = Nokogiri::HTML(open(filename))
      @page_url = filename
    else
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

  def times(el)
    el.css("td")[1].children.select(&:text?).map{|l| l.text.gsub(/\s* and\s*$/,"")}
  end

  def get_info
    @contests = []
    contest_links.each{|l|
      the_link = link(l)
      next if the_link.nil?
      if @page_url
        the_link = URI.join(@page_url,the_link).to_s
      end
      puts "Opening #{the_link}"
      ci = ContestItemParser.new(the_link)
      ci.times = times(l)
      @contests << ci
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

  def contest_details_for_period
    builder = Nokogiri::HTML::Builder.new do |doc|
      doc.html {
        doc.body() {
          #puts "#{@by_date.keys.inspect}"
          already_shown = []
          (Date.parse(self.start_date)..Date.parse(self.end_date)).each { |date|
            #doc.ul {
            date_key = date.strftime("%B %-d")
            puts "looking for #{date_key} #{@by_date[date_key] && @by_date[date_key].length}"


            if @by_date[date_key]
              @by_date[date_key].each { |contest|
                if !already_shown.include?(contest.hash)
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
                    doc.text(contest.bands)
                    doc.text("; ")
                    doc.text(contest.exchange)
                    doc.text("; Logs due: ")
                    doc.text(contest.logs_due)
                    doc.text(".")
                  }
                  doc.br()
                  already_shown << contest.hash
                end
              }
              #}
            end
          }
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
                      doc.text(contest.contest_name)
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

  def contest_details
    #
    #CWops Mini-CWT Test, June 18 0300z-0400z, June 24 1300Z-1400Z,  June 24 1900Z-2000Z,  June 25 0300Z-0400Z, July 1 1300Z-1400Z, July 1 1900Z-2000Z;
    # CW; Bands: 1.8-28MHz;Member: Name + Member No., non-Member: Name + (state/province/country); Logs Due: June 20, June 27, July 4, 2015.
    #
    builder = Nokogiri::HTML::Builder.new do |doc|
      doc.html {
        doc.body() {
          @contests.each { |contest|
            next unless contest.contest_periods.any?{|cp| cp.start_in_period(self.start_date, self.end_date) }
            doc.span {
              doc.a(:href => contest.rules_link) {
                doc.text(contest.contest_name)
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
              doc.text(  contest.bands )
              doc.text( "; " )
              doc.text(contest.exchange)
              doc.text("; Logs due: ")
              doc.text(contest.logs_due)
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
  def self.run!(input_file, output_file_root, start_date_s, end_date_s=nil)
    start_date = DateTime.parse(start_date_s).to_s
    if end_date_s.nil?
      end_date = (DateTime.parse(start_date) + 13 + Rational(86399, 86400) ).to_s
    else
      end_date = DateTime.parse(end_date_s).to_s
    end
    cfd = ContestFragmentParser.new(input_file)
    cfd.start_date = start_date
    cfd.end_date = end_date
    cfd.get_info
    cd = cfd.contest_details
    output_file_details = "#{output_file_root}_details.html"
    output_file_summary = "#{output_file_root}_summary.html"
    output_file_logs_due = "#{output_file_root}_logs_due.html"
    File.open(output_file_details, "w"){ |f| f.write(cd.to_html)}
    File.open(output_file_summary, "w"){ |f| f.write(cfd.contest_summary.to_html)}
    File.open(output_file_logs_due, "w"){ |f| f.write(ContestLogsDueParser.new(start_date, end_date).logs_due.to_html)}

  end
end

class ContestLogsDueParser
  attr_accessor :doc
  def initialize(start_date=nil, end_date=nil)
    @start_date = DateTime.parse(start_date) if start_date
    @end_date = DateTime.parse(end_date) if end_date
    @link = "http://www.hornucopia.com/contestcal/duedates.php"
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