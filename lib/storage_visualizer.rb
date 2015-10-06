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
  
  def initialize(parent_in, dir_name_in, dir_short_in, size_gb_in)
    self.parent = parent_in
    self.dir_name = dir_name_in
    self.dir_short = dir_short_in
    self.size_gb = size_gb_in
    self.children = []
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
  # x Make it work on mac & linux (CentOS & Ubuntu)
  # x Specify blocksize and do not assume 512 bytes (use the -k flag, which reports blocks as KB)
  # x Enable for filesystems not mounted at the root '/'
  # - Allow the threshold to be specified (default is 5%)
  # - Allow output filename to be specified
  # Maybe:
  # x Prevent paths on the graph from crossing (dirs with the same name become the same node)
  # - See if it would be cleaner to use the googlecharts gem (gem install googlecharts)


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
      # puts "Target dir: #{expanded}"
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
  
    # Build the list of nodes
    nodes = []
    nodes.push(self.dir_tree)
    comparison_list = []
    while true
      if (nodes.length == 0)
        break
      end
      node = nodes.shift
      comparison_list.push(node)
      nodes.concat(node.children)
    end
    

    # format the data for the chart
    working_string = "[\n"
    comparison_list.each_with_index do |entry, index|
      if (entry.parent == nil)
        next
      end
      if(index == comparison_list.length - 1)
        # this is the next to last element, it gets no comma
        working_string << "[ '#{entry.parent.dir_short}', '#{entry.dir_short}', #{entry.size_gb} ]\n"
      else
        # mind the comma
        working_string << "[ '#{entry.parent.dir_short}', '#{entry.dir_short}', #{entry.size_gb} ],\n"
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
        data.addColumn('number', 'Size (GB)');
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
    # puts "Determining which volume contains the target directory.."
    self.diskhash.keys.each do |volume|
      result = self.target_dir.gsub(volume, '')
      diskhash['match_amt'] = result.length
      # puts "Considering:\t#{volume}, \t closeness: #{result.length}, \t (#{result})"
      if (result.length < val_of_min)
        # puts "Candidate: #{volume}"
        val_of_min = result.length
        self.target_volume = volume
      end
    end    
    
    puts "Target volume is #{self.target_volume}"
    

    self.capacity   = self.diskhash[self.target_volume]['capacity']
    self.used       = self.diskhash[self.target_volume]['used']
    self.available  = self.diskhash[self.target_volume]['available']

    self.capacity_gb  = "#{'%.0f' % (self.capacity.to_i / 1024 / 1024)}"
    self.used_gb      = "#{'%.0f' % (self.used.to_i / 1024 / 1024)}"
    self.available_gb = "#{'%.0f' % (self.available.to_i / 1024 / 1024)}"

    self.dir_tree = DirNode.new(nil, self.target_volume, self.target_volume, self.capacity)
    self.dir_tree.children.push(DirNode.new(self.dir_tree, 'Free Space', 'Free Space', self.available_gb))

  end
  
  
  # Crawl the dirs recursively, beginning with the target dir
  def analyze_dirs(dir_to_analyze, parent)


    # bootstrap case
    # don't create an entry for the root because there's nothing to link to yet, scan the subdirs
    if (dir_to_analyze == self.target_volume)
      # puts "Dir to analyze is the target volume"
      # run on all child dirs, not this dir
      Dir.entries(dir_to_analyze).reject {|d| d.start_with?('.')}.each do |name|
        # puts "\tentry: >#{file}<"
        full_path = File.join(dir_to_analyze, name)
        if (Dir.exist?(full_path) && !File.symlink?(full_path))
          # puts "Contender: >#{full_path}<"
          analyze_dirs(full_path, self.dir_tree)
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
    capacity_gb = "#{'%.0f' % (self.capacity.to_f / 1024 / 1024)}"
    
    # if this dir contains more than 5% of disk space, add it to the tree

    if (dir_to_analyze == self.target_dir)
      # puts "Dir to analyze is the target dir, space used outside this dir.."
      # account for space used outside of target dir
      other_space = self.used - size
      other_space_gb = "#{'%.0f' % (other_space / 1024 / 1024)}"
      parent.children.push(DirNode.new(parent, self.target_volume, self.target_volume, other_space_gb))
    end
    
    
    if (occupancy > self.threshold_pct)
      # puts "Dir contains more than 5% of disk space: #{dir_to_analyze} \n\tsize:\t#{size_gb} / \ncapacity:\t#{capacity_gb} = #{occupancy_pct}%"
      puts "Dir contains more than 5% of used disk space: #{dir_to_analyze} \n\tsize:\t\t#{size_gb} / \n\toccupancy:\t#{self.used_gb} = #{occupancy_pct}% of used space"

      # puts "Dir to analyze (#{dir_to_analyze}) is not the target dir (#{self.target_dir})"
      dirs = dir_to_analyze.split('/')
      
      short_dir = dirs.pop().gsub("'","\\\\'")
      full_parent = dirs.join('/')
      if (dir_to_analyze == self.target_dir || full_parent == self.target_volume)
        # puts "Either this dir is the target dir, or the parent is the target volume, make parent the full target volume"
        short_parent = self.target_volume.gsub("'","\\\\'")
      else
        # puts "Neither this dir or parent is the target dir, making parent short"
        short_parent = dirs.pop().gsub("'","\\\\'")
      end
      

      this_node = DirNode.new(parent, dir_to_analyze, short_dir, size_gb)
      parent.children.push(this_node)

      # run on all child dirs
      Dir.entries(dir_to_analyze).reject {|d| d.start_with?('.')}.each do |name|
        full_path = File.join(dir_to_analyze, name)
        # don't follow any symlinks
        if (Dir.exist?(full_path) && !File.symlink?(full_path))
          # puts "Contender: >#{full_path}<"
          analyze_dirs(full_path, this_node)
        end
      end
      
    end # occupancy > threshold
      
  end # function
  

  
  def traverse_tree_and_remove_duplicates
    puts "\nHandling duplicate entries.."
    nodes = []
    nodes.push(self.dir_tree)
    comparison_list = []
    while true
      if (nodes.length == 0)
        break
      end
      
      node = nodes.shift
      comparison_list.push(node)
      # pp node
      if node.parent == nil
        # puts "\tparent: no parent \n\tdir:    #{node.dir_name} \n\tshort:  #{node.dir_short} \n\tsize:   #{node.size_gb}"
      else 
        # puts "\tparent: #{node.parent.dir_short.to_s} \n\tdir:    #{node.dir_name} \n\tshort:  #{node.dir_short} \n\tsize:   #{node.size_gb}"
      end
      nodes.concat(node.children)
    end
    # puts "Done building node list"
    
    
    
    for i in 0..comparison_list.length do
      for j in 0..comparison_list.length do
        if (comparison_list[i] != nil && comparison_list[j] != nil)
          if (i != j && comparison_list[i].dir_short == comparison_list[j].dir_short)
            puts "\t#{comparison_list[i].dir_short} is the same as #{comparison_list[j].dir_short}, changing to #{comparison_list[j].dir_short}*"
            comparison_list[j].dir_short = "#{comparison_list[j].dir_short}*"
          end
        end
      end
    end
    puts "Duplicate handling complete"
    
  end
  

  
  def run
    self.get_basic_disk_info
    self.analyze_dirs(self.target_dir, self.dir_tree)
    self.traverse_tree_and_remove_duplicates
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

  # puts "\nRunning visualization"
  vs.run()
  
  # puts "dumping tree: "
  # pp vs.tree
  # puts "Formatted tree\n#{vs.tree_formatted}"
  
end


# Detect whether being called from command line or API. If command line, run
if (File.basename($0) == File.basename(__FILE__))
  # puts "Being called from command line - running"
  run
else 
  # puts "#{__FILE__} being loaded from API, not running"
end


