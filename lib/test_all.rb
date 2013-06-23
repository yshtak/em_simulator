require 'awesome_print'
require './madoka'
require './homra'
require './moppy'

mo1 = Moppy.new({id: 'moppy.1', exchange: 'moppy'})
mo2 = Moppy.new({id: 'moppy.2', exchange: 'moppy'})
mo3 = Moppy.new({id: 'moppy.3', exchange: 'moppy'})
mo4 = Moppy.new({id: 'moppy.4', exchange: 'moppy'})
mo5 = Moppy.new({id: 'moppy.5', exchange: 'moppy'})
mo6 = Moppy.new({id: "moppy.6", exchange: 'moppy'})

madoka1 = Madoka.new({id: "madoka1", exchange: 'madoka.magical'})
madoka2 = Madoka.new({id: "madoka2", exchange: 'madoka.god'})

homra = Homra.new({id: "homra1", topic: 'madoka.magika'})

madoka1.bind_queue 'moppy.1'
madoka1.bind_queue 'moppy.2'
madoka1.bind_queue 'moppy.3'

madoka2.bind_queue 'moppy.5'
madoka2.bind_queue 'moppy.6'
madoka2.bind_queue 'moppy.4'

mo1.bind_queue
mo2.bind_queue
mo3.bind_queue
mo4.bind_queue
mo5.bind_queue
mo6.bind_queue

homra.bind_queue 'moppy'
#homra.bind_queue 'madoka'

madoka1.send_message "ホムラチャン！"
mo1.send_message "test", 'moppy.2'
#homra.send_message_to_route 'あばばばば', 'moppy.1'


sleep
