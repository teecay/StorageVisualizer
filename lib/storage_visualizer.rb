#!/usr/bin/env ruby

# @author Terry Case <terrylcase@gmail.com>

#  Copyright 2015 Terry Case
#  
#  Licensed under the Creative Commons, Version 3.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#  
#      https://creativecommons.org/licenses/by/3.0/us/
#  
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.


require 'pp'
require 'yaml'
require 'date'
require 'uri'
require 'cgi'
require 'json'


class DirNode
  attr_accessor :parent
  attr_accessor :dir_name
  attr_accessor :dir_short
  attr_accessor :size_gb
  attr_accessor :children
  
  def initialize()
  end
  
end




class StorageVisualizer

  # Static
  def self.print_usage
    puts "\nThis tool helps visualize which directories are occupying the most storage. Any directory that occupies more than 5% of disk space is added to a visual hierarchichal storage report in the form of a Google Sankey diagram. The storage data is gathered using the linux `du` utility. It has been tested on Mac OSX, should work on linux systems, will not work on Windows. Run as sudo if analyzing otherwise inaccessible directories. May take a while to run\n"
    puts "\nCommand line usage: \n\t[sudo] storage_visualizer[.rb] [directory to visualize (default ~/) | -h (help) -i | --install (install to /usr/local/bin)]\n\n"
    puts "API usage: "
    puts "\tgem install storage_visualizer"
    puts "\t'require storage_visualizer'"
    puts "\tsv = StorageVisualizer.new('[directory to visualize, ~/ by default]')"
    puts "\tsv.run()\n\n"
    puts "A report will be created in the current directory named as such: StorageReport_2015_05_25-17_19_30.html"
    puts "Status messages are printed to STDOUT"
    puts "\n\n"
  end
  
  
  
  def self.install
    # This function installs a copy & symlink into /usr/local/bin, so the utility can simply be run by typing `storage_visualizer`
    # To install for command line use type:
    # git clone https://github.com/teecay/StorageVisualizer.git && ./StorageVisualizer/storage_visualizer.rb --install
    # To install for gem usage type:
    # gem install storage_visualizer


    script_src_path = File.expand_path(__FILE__) # File.expand_path('./StorageVisualizer/lib/storage_visualizer.rb')
    script_dest_path = '/usr/local/bin/storage_visualizer.rb'
    symlink_path = '/usr/local/bin/storage_visualizer'


    if (!File.exist?(script_src_path))
      raise "Error: file does not exist: #{script_src_path}"
    end


    if (File.exist?(script_dest_path))
      puts "Removing old installed script"
      File.delete(script_dest_path)
    end


    if (File.exist?(symlink_path))
      puts "Removing old symlink"
      File.delete(symlink_path)
    end

    cp_cmd = "cp -f #{script_src_path} #{script_dest_path}"
    puts "Copying script into place: #{cp_cmd}"
    `#{cp_cmd}`

    ln_cmd = "ln -s #{script_dest_path} #{symlink_path}"
    puts "Installing: #{ln_cmd}"
    `#{ln_cmd}`

    chmod_cmd = "chmod ugo+x #{symlink_path}"
    puts "Setting permissions: #{chmod_cmd}"
    `#{chmod_cmd}`

    puts "Installation is complete, run `storage_visualizer -h` for help"
  end
  
  
  # To do:
  # x Make it work on linux
  # x Specify blocksize and do not assume 512 bytes (use the -k flag, which reports blocks as KB)
  # - Enable for filesystems not mounted at the root '/'
  # - Allow the threshold to be specified (default is 5%)
  # - Allow output filename to be specified
  # Maybe:
  # - Prevent paths on the graph from crossing (dirs with the same name become the same node)
  # - See if it would be cleaner to use the googlecharts gem (gem install googlecharts)
  # - Create an installer that sets up cron scheduling and add polling to the webpage


  # disk Bytes
  attr_accessor :capacity
  attr_accessor :used
  attr_accessor :available
  # disk GB for display
  attr_accessor :capacity_gb
  attr_accessor :used_gb
  attr_accessor :available_gb
  # other 
  attr_accessor :target_dir
  attr_accessor :tree
  attr_accessor :tree_formatted
  attr_accessor :diskhash
  attr_accessor :threshold_pct
  attr_accessor :target_volume
  attr_accessor :dupe_counter

  # this is the root DirNode object 
  attr_accessor :dir_tree

  # Constructor
  def initialize(target_dir_passed = nil)

    if (target_dir_passed != nil)
      expanded = File.expand_path(target_dir_passed)
      puts "Target dir: #{expanded}"
      if (Dir.exist?(expanded))
        self.target_dir = expanded
      else
        raise "Target directory does not exist: #{expanded}"
      end
    else
      # no target passed, use the user's home dir
      self.target_dir = File.expand_path('~')
    end
    
    # how much space is considered worthy of noting on the chart
    self.threshold_pct = 0.05
    self.diskhash = {}
    self.tree = []
    self.tree_formatted = ''
    self.dupe_counter = 0
  end
  
  
  
  def format_data_for_the_chart
    working_string = "[\n"
    
    self.tree.each_with_index do |entry, index|
      if(index == self.tree.length - 1)
        # this is the next to last element, it gets no comma
        working_string << "[ '#{entry[0]}', '#{entry[1]}', #{entry[2]} ]\n"
      else
        # mind the comma
        working_string << "[ '#{entry[0]}', '#{entry[1]}', #{entry[2]} ],\n"
      end
    end
    working_string << "]\n"
    self.tree_formatted = working_string
    
  end
  
  
  def write_storage_report
  
    the_html = %q|<html>
    <body>
    <script type="text/javascript"
          src="https://www.google.com/jsapi?autoload={'modules':[{'name':'visualization','version':'1.1','packages':['sankey']}]}">
    </script>
    
    <style>
      td
        {
          font-family:sans-serif;
          font-size:8pt;
        }

      .bigger
          {
            font-family:sans-serif;
            font-size:10pt;
            font-weight:bold
          }
    
    </style>

    <div class="table">
      <div class="bigger">Storage Report</div>
      <table>
        <tr>
          <td style="text-align:right">Disk Capacity:</td><td>| + self.capacity_gb + %q| GB</td>
        </tr>
        <tr>
          <td style="text-align:right">Disk Used:</td><td>| + self.used_gb + %q| GB</td>
        </tr>
        <tr>
          <td style="text-align:right">Free Space:</td><td>| + self.available_gb + %q| GB</td>
        </tr>
      </table>
          
    </div>


    <div id="sankey_multiple" style="width: 900px; height: 300px;"></div>

    <script type="text/javascript">

    google.setOnLoadCallback(drawChart);
       function drawChart() {
        var data = new google.visualization.DataTable();
        data.addColumn('string', 'From');
        data.addColumn('string', 'To');
        data.addColumn('number', 'Weight');
        data.addRows( | + self.tree_formatted + %q|);

        // Set chart options
        var options = {
        
              width: 1000,
              sankey: {
                iterations: 32,
                node: { label: { 
                          fontName: 'Arial',
                          fontSize: 10,
                          color: '#871b47',
                          bold: false,
                          italic: true } } }, 
            };
            
            
            
        // Instantiate and draw our chart, passing in some options.
        var chart = new google.visualization.Sankey(document.getElementById('sankey_multiple'));
        chart.draw(data, options);
       }
       
       
    </script>
    </body>
    </html>|
    
    
    filename = DateTime.now.strftime("./StorageReport_%Y_%m_%d-%H_%M_%S.html")
    puts "Writing html file #{filename}"
    f = File.open(filename, 'w+')
    f.write(the_html)
    f.close
    
  end
  
  
  def get_basic_disk_info
    # df -l gets info about locally-mounted filesystems
    output = `df -lk`
    
    # OSX:
    #   Filesystem                          1024-blocks  Used      Available   Capacity   iused     ifree       %iused  Mounted on
    #   /dev/disk1                          975912960    349150592 626506368   36%        87351646  156626592   36%     /
    #   localhost:/QwnJE6UBvlR1EvqouX6gMM   975912960    975912960         0   100%        0         0          100%    /Volumes/MobileBackups
    
    # CentOS:
    #   Filesystem     1K-blocks    Used Available Use% Mounted on
    #   /dev/xvda1      82436764 3447996  78888520   5% /
    #   devtmpfs        15434608      56  15434552   1% /dev
    #   tmpfs           15443804       0  15443804   0% /dev/shm
    
    # Ubuntu:
    #   Filesystem     1K-blocks   Used Available Use% Mounted on
    #   /dev/xvda1      30832636 797568  28676532   3% /
    #   none                   4      0         4   0% /sys/fs/cgroup
    #   udev             3835900     12   3835888   1% /dev
    #   tmpfs             769376    188    769188   1% /run
    #   none                5120      0      5120   0% /run/lock
    #   none             3846876      0   3846876   0% /run/shm
    #   none              102400      0    102400   0% /run/user
    #   /dev/xvdb       30824956  45124  29207352   1% /mnt

    # Populate disk info into a hash of hashes
    # {"/"=>
    #   {"capacity"=>498876809216, "used"=>434777001984, "available"=>63837663232},
    #  "/Volumes/MobileBackups"=>
    #   {"capacity"=>498876809216, "used"=>498876809216, "available"=>0}
    # }

    # get each mount's capacity & utilization
    output.lines.each_with_index do |line, index|
      if (index == 0)
        # skip the header line
        next
      end
      cols = line.split
      # ["Filesystem", "1024-blocks", "Used", "Available", "Capacity", "iused", "ifree", "%iused", "Mounted", "on"]
      # line: ["/dev/disk1", "974368768", "849157528", "124699240", "88%", "106208689", "15587405", "87%", "/"]
      
      if cols.length == 9
        # OSX
        self.diskhash[cols[8]] = {
          'capacity' => (cols[1].to_i ).to_i,
          'used' => (cols[2].to_i ).to_i,
          'available' => (cols[3].to_i ).to_i
        }
      elsif cols.length == 6
        # Ubuntu & CentOS
        self.diskhash[cols[5]] = {
          'capacity' => (cols[1].to_i ).to_i,
          'used' => (cols[2].to_i ).to_i,
          'available' => (cols[3].to_i ).to_i
        }
      else
        raise "Reported disk utilization not understood"
      end
    end

    # puts "Disk mount info:"
    # pp diskhash


    # find the (self.)target_volume 
    # look through diskhash keys, to find the one that most matches target_dir
    val_of_min = 1000
    puts "Determining which volume contains the target directory.."
    self.diskhash.keys.each do |volume|
      result = self.target_dir.gsub(volume, '')
      diskhash['match_amt'] = result.length
      puts "Considering:\t#{volume}, \t closeness: #{result.length}, \t (#{result})"
      if (result.length < val_of_min)
        puts "Candidate: #{volume}"
        val_of_min = result.length
        self.target_volume = volume
      end
    end    
    
    
    
    # set the capacity and utilization of the ROOT mount
    # CHANGE THIS TO BE THE CAPACITY & UTILIZATION OF THE TARGET MOUNT
    # self.capacity = self.diskhash['/']['capacity']
    # self.used = self.diskhash['/']['used']
    # self.available = self.diskhash['/']['available']


    self.capacity   = self.diskhash[self.target_volume]['capacity']
    self.used       = self.diskhash[self.target_volume]['used']
    self.available  = self.diskhash[self.target_volume]['available']



    free_space = (self.available).to_i
    free_space_gb = "#{'%.0f' % (free_space / 1024 / 1024)}"

    free_space_array = [self.target_volume, 'Free Space', free_space_gb]
    self.tree.push(free_space_array)

    self.capacity_gb  = "#{'%.0f' % (self.capacity.to_i / 1024 / 1024)}"
    self.used_gb      = "#{'%.0f' % (self.used.to_i / 1024 / 1024)}"
    self.available_gb = "#{'%.0f' % (self.available.to_i / 1024 / 1024)}"



  end
  
  
  # Crawl the dirs recursively, beginning with the target dir
  def analyze_dirs(dir_to_analyze)

    # bootstrap case
    # don't create an entry for the root because there's nothing to link to yet, scan the subdirs
    if (dir_to_analyze == self.target_volume)
      puts "Dir to analyze is the target volume"
      # run on all child dirs, not this dir
      Dir.entries(dir_to_analyze).reject {|d| d.start_with?('.')}.each do |name|
        # puts "\tentry: >#{file}<"
        full_path = File.join(dir_to_analyze, name)
        if (Dir.exist?(full_path) && !File.symlink?(full_path))
          # puts "Contender: >#{full_path}<"
          analyze_dirs(full_path)
        end
      end
      return
    end

    # use "P" to help prevent following any symlinks
    cmd = "du -sxkP \"#{dir_to_analyze}\""
    puts "\trunning #{cmd}"
    output = `#{cmd}`.strip().split("\t")
    # puts "Du output:"
    # pp output
    size = output[0].to_i 
    size_gb = "#{'%.0f' % (size.to_f / 1024 / 1024)}"
    # puts "Size: #{size}\nCapacity: #{self.diskhash['/']['capacity']}"
    
    # Occupancy as a fraction of total space
    # occupancy = (size.to_f / self.capacity.to_f)

    # Occupancy as a fraction of USED space
    occupancy = (size.to_f / self.used.to_f)

    occupancy_pct = "#{'%.0f' % (occupancy * 100)}"
    occupancy_gb = "#{'%.0f' % (occupancy.to_f / 1024 / 1024)}"
    capacity_gb = "#{'%.0f' % (self.capacity.to_f / 1024 / 1024)}"
    
    # if this dir contains more than 5% of disk space, add it to the tree
    
    
    if (occupancy > self.threshold_pct)
      # puts "Dir contains more than 5% of disk space: #{dir_to_analyze} \n\tsize:\t#{size_gb} / \ncapacity:\t#{capacity_gb} = #{occupancy_pct}%"
      puts "Dir contains more than 5% of used disk space: #{dir_to_analyze} \n\tsize:\t#{size_gb} / \noccupancy:\t#{occupancy_gb} = #{occupancy_pct}% of used space"
      # push this dir's info
      
      if (dir_to_analyze == self.target_dir)

        puts "Dir to analyze is the target dir"
        # account for space used outside of target dir
        other_space = self.used - size
        other_space_gb = "#{'%.0f' % (other_space / 1024 / 1024)}"
        other_space_array = [self.target_volume, 'Other', other_space_gb]

        short_target_dir = self.target_dir.split('/').reverse[0]
        short_target_dir = (short_target_dir == nil) ? self.target_dir : short_target_dir

        # comparison = ['/', short_target_dir, size_gb]
        comparison = [self.target_volume, short_target_dir, size_gb]
        
        # add them to the array
        self.tree.push(other_space_array)
        self.tree.push(comparison)

      else
        # get parent dir and add to the tree
        # short_parent = dir_to_analyze.split('/').reverse[1]
        # short_parent = (short_parent == nil) ? parent : short_parent
        # case for when parent is '/'
        # short_parent = (short_parent == '') ? '/' : short_parent
        # short_dir = dir_to_analyze.split('/').reverse[0]
        
        # push the full dir name
        # parent = dir_to_analyze[0..dir_to_analyze.rindex('/')-1]
        # array_to_push = [parent, dir_to_analyze, size_gb]
        # Just push the short dir and parent name 
        # Leads to circular references, chart will not always render
        # array_to_push = [short_parent, short_dir, size_gb]

        # TODO: XML-encode node entries
        # TODO: why are there duplicates for backup dirs? symlinks? try adding the P switch


        # get 2 deep for parent and dir_to_analyze
        # Produces very long output, abort
        # dirs = dir_to_analyze.split('/')
        # if (dirs.length >= 4)
        #   parent = ".../#{dirs.reverse()[2]}/#{dirs.reverse()[1]}"
        #   this_dir = ".../#{dirs.reverse()[1]}/#{dirs.reverse()[0]}"
        # elsif (dirs.length == 3) 
        #   parent = "/#{dirs.reverse()[2]}/#{dirs.reverse()[2]}/#{dirs.reverse()[1]}"
        #   this_dir = ".../#{dirs.reverse()[1]}/#{dirs.reverse()[0]}"
        # elsif (dirs.length == 2)
        #   parent = "/#{dirs.reverse()[1]}"
        #   this_dir = "/#{dirs.reverse()[1]}/#{dirs.reverse()[0]}"
        # end

        


        puts "Dir to analyze (#{dir_to_analyze}) is not the target dir (#{self.target_dir})"
        dirs = dir_to_analyze.split('/')
        
        this_dir = dirs.pop().gsub("'","\\\\'")
        full_parent = (dirs.length == 1) ? '/' : dirs.join('/')
        if (full_parent == self.target_volume)
          parent = full_parent.gsub("'","\\\\'")
        else
          parent = dirs.pop().gsub("'","\\\\'")
        end

        # build full tree here
        # later reduce node size & deal with circulaar references

        # deal with circular references
        # if self.tree[0-n][0] == this_dir, rename this_dir
        self.tree.each do |entry|
          if (entry[0] == this_dir)
            self.dupe_counter = self.dupe_counter + 1
            this_dir = "#{this_dir} (#{self.dupe_counter})"
          end
        end

        array_to_push = [parent, this_dir, size_gb]
        self.tree.push(array_to_push)
      end

      # run on all child dirs
      Dir.entries(dir_to_analyze).reject {|d| d.start_with?('.')}.each do |name|
        # puts "\tentry: >#{file}<"
        
        full_path = File.join(dir_to_analyze, name)
        
        # don't follow any symlinks
        if (Dir.exist?(full_path) && !File.symlink?(full_path))
          # puts "Contender: >#{full_path}<"
          analyze_dirs(full_path)
        end
      end
      
    end
      
  end
  
  
  def run
    self.get_basic_disk_info
    self.analyze_dirs(self.target_dir)
    self.format_data_for_the_chart
    self.write_storage_report
    
  end
  
end



def run
  
  if (ARGV.length > 0)
    if (ARGV[0] == '-h')
      StorageVisualizer.print_usage()
      return
    elsif (ARGV[0] == '-i' || ARGV[0] == '--install')
      StorageVisualizer.install
      StorageVisualizer.print_usage
      return
    end
    vs = StorageVisualizer.new(ARGV[0])
  else
    vs = StorageVisualizer.new()
  end

  puts "\nRunning visualization"
  vs.run()
  
  # puts "dumping tree: "
  # pp vs.tree
  puts "Formatted tree\n#{vs.tree_formatted}"
  
end


# Detect whether being called from command line or API. If command line, run
if (File.basename($0) == File.basename(__FILE__))
  # puts "Being called from command line - running"
  run
else 
  # puts "#{__FILE__} being loaded from API, not running"
end


