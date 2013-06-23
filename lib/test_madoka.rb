require './madoka'

madoka = Madoka.new({id: 'test'})

madoka.bind_queue "madoka1"
madoka.bind_queue "madoka2"
madoka.bind_queue "madoka3"


madoka.send_message("メッセージングPingテスト")

sleep

#madoka.delete_exchange
#madoka.close

