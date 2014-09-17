
/*
 * lcd2usb.c - test application for the lcd2usb interface
 *             http://www.harbaum.org/till/lcd2usb
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <usb.h>

#include<errno.h>
#include<sys/stat.h>
#include<fcntl.h>


/* vendor and product id */
#define LCD2USB_VID  0x0403
#define LCD2USB_PID  0xc630

/* target is a bit map for CMD/DATA */
#define LCD_CTRL_0         (1<<3)
#define LCD_CTRL_1         (1<<4)
#define LCD_BOTH           (LCD_CTRL_0 | LCD_CTRL_1)

#define LCD_ECHO           (0<<5)
#define LCD_CMD            (1<<5)
#define LCD_DATA           (2<<5)
#define LCD_SET            (3<<5)
#define LCD_GET            (4<<5)

/* target is value to set */
#define LCD_SET_CONTRAST   (LCD_SET | (0<<3))
#define LCD_SET_BRIGHTNESS (LCD_SET | (1<<3))
#define LCD_SET_RESERVED0  (LCD_SET | (2<<3))
#define LCD_SET_RESERVED1  (LCD_SET | (3<<3))

/* target is value to get */
#define LCD_GET_FWVER      (LCD_GET | (0<<3))
#define LCD_GET_KEYS       (LCD_GET | (1<<3))
#define LCD_GET_CTRL       (LCD_GET | (2<<3))
#define LCD_GET_RESERVED1  (LCD_GET | (3<<3))

#ifdef WIN
#include <windows.h>
#include <winbase.h>
#define MSLEEP(a) Sleep(a)
#else
#define MSLEEP(a) usleep(a*1000)
#endif

#define LCD_BTN_DELAY 150

int FIELD_SIZE=0;


usb_dev_handle      *handle = NULL;

/**********clover**************/
/* Save volume name and fsck  */
/* progress to show on LCD    */
typedef struct PrintOnLCD
{
	char volume[30];
	char progress[30];
}Print_To_LCD;
/****************************/
int lcd_send(int request, int value, int index) {
	if(usb_control_msg(handle, USB_TYPE_VENDOR, request,value, index, NULL, 0, 1000) < 0) {
    		fprintf(stderr, "USB request failed!");
		return -1;
	}
	return 0;
}
/* to increase performance, a little buffer is being used to */
/* collect command bytes of the same type before transmitting them */
#define BUFFER_MAX_CMD 4        /* current protocol supports up to 4 bytes */
int buffer_current_type = -1;   /* nothing in buffer yet */
int buffer_current_fill = 0;    /* -"- */
int DISK_NUM = 0; //update when startup
int MAX_MD = 0;
unsigned char buffer[BUFFER_MAX_CMD];

/* command format:
 * 7 6 5 4 3 2 1 0
 * C C C T T R L L
 *
 * TT = target bit map
 * R = reserved for future use, set to 0
 * LL = number of bytes in transfer - 1
 */

/* flush command queue due to buffer overflow / content */
/* change or due to explicit request */
void lcd_flush(void) {
	int request, value, index;

  	/* anything to flush? ignore request if not */
	if (buffer_current_type == -1)
    	return;

  	/* build request byte */
	request = buffer_current_type | (buffer_current_fill - 1);

  	/* fill value and index with buffer contents. endianess should IMHO not */
  	/* be a problem, since usb_control_msg() will handle this. */
  	value = buffer[0] | (buffer[1] << 8);
  	index = buffer[2] | (buffer[3] << 8);

  	/* send current buffer contents */
  	lcd_send(request, value, index);

  	/* buffer is now free again */
  	buffer_current_type = -1;
  	buffer_current_fill = 0;
}
/* enqueue a command into the buffer */
void lcd_enqueue(int command_type, int value) {
	if ((buffer_current_type >= 0) && (buffer_current_type != command_type))
		lcd_flush();

  	/* add new item to buffer */
  	buffer_current_type = command_type;
  	buffer[buffer_current_fill++] = value;

  	/* flush buffer if it's full */
  	if (buffer_current_fill == BUFFER_MAX_CMD)
    		lcd_flush();
}
/* see HD44780 datasheet for a command description */
void lcd_command(const unsigned char ctrl, const unsigned char cmd) {
  	lcd_enqueue(LCD_CMD | ctrl, cmd);
}
/* clear display */
void lcd_clear(void) {
  	lcd_command(LCD_BOTH, 0x01);    /* clear display */
  	lcd_command(LCD_BOTH, 0x03);    /* return home */
}
/* home display */
void lcd_home(void) {
  	lcd_command(LCD_BOTH, 0x03);    /* return home */
}

void lcd_move_cursor_right(void) {
  	lcd_command(LCD_BOTH, 0x14);
}

void lcd_jump_sec_line(void) {
  	int i;
  	lcd_home();
  	for(i=0;i<40;i++) {
    		lcd_move_cursor_right();
  	}
}
/* write a data string to the first display */
void lcd_write(const char *data) {
  	int ctrl = LCD_CTRL_0;

  	while(*data)
		lcd_enqueue(LCD_DATA | ctrl, *data++);

  	lcd_flush();
}
/* send a number of 16 bit words to the lcd2usb interface */
/* and verify that they are correctly returned by the echo */
/* command. This may be used to check the reliability of */
/* the usb interfacing */
#define ECHO_NUM 100
void lcd_echo(void) {

	int i, nBytes, errors=0;
		unsigned short val, ret;

	for(i=0;i<ECHO_NUM;i++) {
		val = rand() & 0xffff;
		nBytes = usb_control_msg(handle,USB_TYPE_VENDOR | USB_RECIP_DEVICE |USB_ENDPOINT_IN,LCD_ECHO, val, 0,(char*)&ret, sizeof(ret), 1000);
		if(nBytes < 0) {
			fprintf(stderr, "USB request failed!");
			return;
		}
		if(val != ret)
			errors++;
	}

	if(errors)
		fprintf(stderr, "ERROR: %d out of %d echo transfers failed!\n", errors, ECHO_NUM);
	else
		printf("Echo test successful!\n");
}
/* get a value from the lcd2usb interface */
int lcd_get(unsigned char cmd) {
  	unsigned char       buffer[2];
  	int                 nBytes;

  	/* send control request and accept return value */
  	nBytes = usb_control_msg(handle,USB_TYPE_VENDOR | USB_RECIP_DEVICE |
  		USB_ENDPOINT_IN,cmd, 0, 0, (char *)buffer, sizeof(buffer), 1000);

  	if(nBytes < 0) {
		fprintf(stderr, "USB request failed!");
		return -1;
  	}

  	return buffer[0] + 256*buffer[1];
}
/* get lcd2usb interface firmware version */
void lcd_get_version(void) {
  	int ver = lcd_get(LCD_GET_FWVER);
  	if(ver != -1)
		printf("Firmware version %d.%d\n", ver&0xff, ver>>8);
}
/* get the bit mask of installed LCD controllers (0 = no */
/* lcd found, 1 = single controller display, 3 = dual */
/* controller display */
void lcd_get_controller(void) {
  	int ctrl = lcd_get(LCD_GET_CTRL);
	if(ctrl != -1) {
		if(ctrl)
			printf("Installed controllers: %s%s\n",(ctrl&1)?"CTRL0":"",(ctrl&2)?" CTRL1":"");
		else
			printf("No controllers installed!\n");
	}
}

/* get state of the two optional buttons */
int lcd_get_keys(void) {
  	int keymask = lcd_get(LCD_GET_KEYS);

/* add S3, S4 buttons support, hammer */
/*
  	if(keymask != -1)
    		printf("Keys: 0:%s 1:%s 2:%s 3:%s\n",
	   		(keymask&1)?"on":"off",
	   		(keymask&2)?"on":"off",
	   		(keymask&4)?"on":"off",
	   		(keymask&8)?"on":"off");
*/
	return keymask;
}

/* set a value in the LCD interface */
void lcd_set(unsigned char cmd, int value) {
  	if(usb_control_msg(handle, USB_TYPE_VENDOR, cmd, value, 0, NULL, 0, 1000) < 0) {
    		fprintf(stderr, "USB request failed!");
  	}
}

/* set contrast to a value between 0 and 255. Result depends */
/* display type */
void lcd_set_contrast(int value) {
  	lcd_set(LCD_SET_CONTRAST, value);
}

/* set backlight brightness to a value between 0 (off) anf 255 */

void lcd_set_brightness(int value) {
  	lcd_set(LCD_SET_BRIGHTNESS, value);
}

void flush_cursor(int blink,int length,int index, char *kstring){
	kstring[length] = '\0';
	if (blink == 1){
		char old_string[length + 1];
		strcpy(old_string,kstring);
		old_string[index] = 176;
		lcd_jump_sec_line();
		lcd_write(old_string);
	}
	else{
		lcd_jump_sec_line();
		lcd_write(kstring);
	}
}

/*** get volume name & progress % ************
 show on LCD for watch dog do fsck in booting
**********************************************/
void get_vol_prgs(char *source,const char *delim,Print_To_LCD *pt)
{
	char *CutFsckMsg,*FindVG=NULL,*FindPRG=NULL;
        CutFsckMsg=strtok(source,delim);                //cut to token
	FILE *log;
	log = fopen("/DOM/.fsck.log","a+");
	if( log== NULL)
		return ;
        while(CutFsckMsg)
        {
		
		fputs(CutFsckMsg,log);
		fputs(" ",log);
                FindVG=strstr(CutFsckMsg,"VG");         //find out token with VG string
                FindPRG=strstr(CutFsckMsg,"%");         //find out the token have "%"

                /*********CutFsckMsg will be device path like: /dev/zvol/VG01/shared
                so we need get the "VGxx/xxx" from pathname like:"VG01/shared"  
		*********************************************************************/

                if(FindVG)                      //get VGXX in pathname
                {
                        sprintf(pt->volume,"check %s",FindVG);        //save string after "VG"
                        FindVG=NULL;
                }
                else if(FindPRG)                                // save "yy%" to struct
                {
                        sprintf(pt->progress,"repairing %s",CutFsckMsg);
                }
                CutFsckMsg=strtok(NULL,delim);
        }
	fclose(log);
}

int main (int argc, char *argv[]){
	struct usb_bus      *bus;
	struct usb_device   *dev;
	char buf_r[100];		/* buf for FIFO content*/
	char *delim=" :=|\\-";		/* using in strtok to pass it */
	FILE *fp;				/* FIFO */
	int wait_to_showLCD=0;		/*more smoonth to show msg on LCD*/
	Print_To_LCD *ptl;
	ptl = (Print_To_LCD *)malloc(sizeof(Print_To_LCD));	
	
	usb_init();
	usb_find_busses();
	usb_find_devices();
	for(bus = usb_get_busses(); bus; bus = bus->next) {
		for(dev = bus->devices; dev; dev = dev->next) {
			if((dev->descriptor.idVendor == LCD2USB_VID) && (dev->descriptor.idProduct == LCD2USB_PID)) {
				printf("Found LCD2USB device on bus %s device %s.\n",bus->dirname, dev->filename);
				/* open device */
				if(!(handle = usb_open(dev)))
					fprintf(stderr, "Error: Cannot open USB device: %s\n", usb_strerror());
				break;
			}
		}
	}
	if(!handle) {
		fprintf(stderr, "Error: Could not find LCD2USB device\n");
		//system("touch /proNAS/isSES");
		#ifdef WIN
		printf("Press return to quit\n");
		getchar();
		#endif
		exit(-1);
	}
  	/* make lcd interface return some bytes to */
  	/* test transfer reliability */
  	lcd_echo();

  	/* read some values from adaptor */
  	lcd_get_version();
  	lcd_get_controller();
  	//lcd_get_keys();

 	 /* adjust contrast and brightess */
  	lcd_set_contrast(200);
  	lcd_set_brightness(255);

  	/* clear display */
  	//lcd_clear();
	
	
	
	fp = fopen(argv[1],"r");
    	if(fp==NULL)
    	{
       		perror("can't open file");
        	exit(1);
    	}

    	while(1)
    	{
		wait_to_showLCD++;
        	if(feof(fp))
			break;     	        
		
		fgets(buf_r,99,fp);
		
		get_vol_prgs(buf_r,delim,ptl);
		if(wait_to_showLCD == 1 )
		{
                        lcd_clear();
                        lcd_write(ptl->volume);
                        lcd_jump_sec_line();
                        lcd_write(ptl->progress);

		}
		else if(wait_to_showLCD >= 5 )
		{		
			lcd_clear();
			lcd_write(ptl->volume);
			lcd_jump_sec_line();
			lcd_write(ptl->progress);
			wait_to_showLCD=0;	   
		}
		usleep(100000);
    	}
	lcd_clear();
	lcd_write("Waiting booting");
        lcd_jump_sec_line();
        lcd_write("");

	fclose(fp);
	free(ptl);
	usb_close(handle);

	return 0;

}


