from PIL import Image
import sys


def convertImage(name):
   im = Image.open(name)
   (s,s,width,height)=im.getbbox()
   print(width,height)
   count = 0
   for y in range(height):
    for x in range(width):
        count = count+1
        pixel = im.getpixel((x,y))
        # AGBR ?
        # 00 00
        byte1 = ((pixel[0] ) &0xF0) | ((pixel[1] >> 4)&0x0F)
        byte2 = ((pixel[2] ) &0xF0)
        sys.stdout.write('{:02X} '.format(byte1))
        sys.stdout.write('{:02X} '.format(byte2))
        #sys.stdout.write('{:02X} '.format(pixel[0]))
        #sys.stdout.write('{:02X} '.format(pixel[1]))
        #sys.stdout.write('{:02X} '.format(pixel[2]))
        #sys.stdout.write('{:02X} '.format(00))
        #
        # 16:  4 4 4 4 ?
        if (not (count % 4)):
            print('')
if __name__ == "__main__":
  #print(sys.argv[1])
  convertImage(sys.argv[1])
