
# gem build storage_visualizer.gemspec
# gem push storage_visualizer-0.0.1.gem

Gem::Specification.new do |s|
  s.name        = 'storage_visualizer'
  s.version     = '0.0.8'
  s.date        = '2015-10-05'
  s.summary     = 'Creates a webpage showing which directories occupy the most storage using a Google Sankey diagram'
  s.description = 'This tool helps visualize which directories are occupying the most storage. Any directory that occupies more than 5% of used disk space is added to a visual hierarchichal storage report in the form of a Google Sankey diagram. The storage data is gathered using the linux `du` utility. It has been tested on Mac OSX and linux systems (Ubuntu & CentOS), will not work on Windows. Run as sudo if analyzing otherwise inaccessible directories. May take a while to run.'
  s.authors     = ['Terry Case']
  s.email       = 'terrylcase@gmail.com'
  s.files       = ['lib/storage_visualizer.rb']
  s.homepage    = 'https://github.com/teecay/StorageVisualizer'
  s.license     = 'Creative Commons Attribution 3.0 License'
end


