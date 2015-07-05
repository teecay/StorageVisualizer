#!/usr/bin/env ruby

gem_cmd = "gem install 'storage_visualizer'"
puts "Installing storage_visualizer gem: #{gem_cmd}"
`#{gem_cmd}`

script_path = "#{Gem::Specification.find_by_name('storage_visualizer').gem_dir}/lib/storage_visualizer.rb"
symlink_path = '/usr/local/bin/storage_visualizer'

if (File.exist?(symlink_path))
  puts "Removing old symlink"
  File.delete(symlink_path)
end


# ln -s /Users/terry/Dev/utils/visualize_storage.rb /usr/local/bin/visualize_storage.rb
ln_cmd = "ln -s #{script_path} #{symlink_path}"
puts "Installing: #{ln_cmd}"
`#{ln_cmd}`

chmod_cmd = "chmod ugo+x #{symlink_path}"
puts "Setting permissions: #{chmod_cmd}"
`#{chmod_cmd}`

puts "Installation is complete, run `storage_visualizer -h` for help"