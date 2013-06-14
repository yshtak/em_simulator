require './auction_tread'
require 'awesome_print'
at = AuctionThread.new({weather: 'sunny'})
#at.init_date
at.destroy
p at.get_thread
(0..365).each{|j|
 (0..95).each{|i|
  at.update_price(Random.rand(230.0))
  (0..rand(88)).each{|i| at.inc_buyer}
  at.next_step
 }
 at.done_auction
 case rand(3)
 when 0
  at.init_date 'sunny'
 when 1
  at.init_date 'cloudy'
 when 2
  at.init_date 'rainy'
 end
 
}
#ap at.get_thread
##
#at.destroy
#ap at.get_weekly_threads 'sunny'
ap at.get_weekly_threads( 'rainy').size
#ap at.get_weekly_threads 'cloudy'

