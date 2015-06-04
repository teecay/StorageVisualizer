## Storage Visualizer

##### This tool helps visualize which directories are occupying the most storage. Any directory that occupies more than 5% of disk space is added to a visual hierarchichal storage report in the form of a Google Sankey diagram. The storage data is gathered using the linux `du` utility. It has been tested on Mac OSX, CentOS, and Ubuntu - will not work on Windows. Run as sudo if analyzing otherwise inaccessible directories. May take a while to run

##### Command line usage:

	[sudo] ./visualize_storage.rb [directory to visualize (default ~/) | -h (help) -i | --install (install to /usr/local/bin)]

##### API usage: 	

	'require storage_visualizer'"
	sv = StorageVisualizer.new('[directory to visualize, ~/ by default]')
	sv.run()

##### A report will be created in the current directory named as such: StorageReport_2015_05_25-17_19_30.html
##### Status messages are printed to STDOUT
