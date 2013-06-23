require './moppy'

puts ARGV[0]
mo = Moppy.new({id: ARGV[0]})
mo.start

sleep
