import pyudev as pu

# Initialize the context for accessing udev
context = pu.Context()


class Fields:
    BUSNUM = 'BUSNUM'
    DEVICENAME = "DEVNAME"

def add_properties(device, d ):
    n = {}
    n.update(d)
    if device is not None:
        for k in device.keys():
           n[k] = device.get(k)
    return n


def device_as_dict(device):
   d = {}
   d = add_properties(device.parent.parent,d)
   d = add_properties(device.parent,d)
   d = add_properties(device,d)
   return d


def load_video_capture_devices():
  capture_devices = []
  for d in context.list_devices(subsystem='video4linux'):
    q = device_as_dict(d)

    if 'ID_V4L_CAPABILITIES' in q.keys():
        if q['ID_V4L_CAPABILITIES'] == ':capture:':
           capture_devices.append(q)
  return capture_devices


ALL_CAPTURE_DEVICES = load_video_capture_devices()


def find_device_by_attribute(attr_name, attr_value ):
    for d in ALL_CAPTURE_DEVICES:
       if d[attr_name] == attr_value:
         return d
    return None

def device_by_bus(bus_num):
    d = find_device_by_attribute(Fields.BUSNUM,bus_num)
    return d

def make_simple_device_map():
    simple_device_map = {}
    for d in ALL_CAPTURE_DEVICES:
        bus_num = d[Fields.BUSNUM]
        device = d[Fields.DEVICENAME]

        simple_device_map[bus_num] = device
    return simple_device_map

DEVICE_MAP = make_simple_device_map()

if __name__ ==  '__main__':
    print ( "Bus7=",device_by_bus('007')['DEVNAME'])
    print ( "Bus5=",device_by_bus('005')['DEVNAME'])
    print ( "Bus3=",device_by_bus('003'))