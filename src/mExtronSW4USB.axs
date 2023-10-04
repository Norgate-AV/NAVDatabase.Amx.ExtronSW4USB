MODULE_NAME='mExtronSW4USB'     (
                                    dev vdvObject,
                                    dev dvPort
                                )

(***********************************************************)
#include 'NAVFoundation.ModuleBase.axi'

/*
 _   _                       _          ___     __
| \ | | ___  _ __ __ _  __ _| |_ ___   / \ \   / /
|  \| |/ _ \| '__/ _` |/ _` | __/ _ \ / _ \ \ / /
| |\  | (_) | | | (_| | (_| | ||  __// ___ \ V /
|_| \_|\___/|_|  \__, |\__,_|\__\___/_/   \_\_/
                 |___/

MIT License

Copyright (c) 2023 Norgate AV Services Limited

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

(***********************************************************)
(*          DEVICE NUMBER DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_DEVICE

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT

constant long TL_DRIVE    = 1


constant integer MAX_LEVELS = 3
constant char LEVELS[][NAV_MAX_CHARS]    = { 'ALL',
                        'VID',
                        'AUD' }

constant char LEVEL_COMMANDS[][NAV_MAX_CHARS]    = { '!',
                            '%',
                            '$' }

constant integer MAX_OUTPUTS = 1


constant integer COMM_MODE_TWO_WAY = 1
constant integer COMM_MODE_ONE_WAY = 2
(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE

volatile long ltDrive[] = { 200 }

volatile long ltFeedback[] = { 200 }

volatile integer iLoop

volatile integer iSemaphore
volatile char cRxBuffer[NAV_MAX_BUFFER]

volatile integer iModuleEnabled

volatile integer iCommandBusy

volatile integer iOutputRequired[MAX_LEVELS][MAX_OUTPUTS]
volatile integer iPendingRequired[MAX_LEVELS][MAX_OUTPUTS]    //Specific pending status for each level
volatile integer iPending    //General pending status

volatile integer iOutputActual[MAX_LEVELS][MAX_OUTPUTS]

volatile integer iCommunicating

volatile integer iNumberOfInputs
volatile integer iInputHasSignal[8]

volatile integer iCommMode = COMM_MODE_TWO_WAY

(***********************************************************)
(*               LATCHING DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_LATCHING

(***********************************************************)
(*       MUTUALLY EXCLUSIVE DEFINITIONS GO BELOW           *)
(***********************************************************)
DEFINE_MUTUALLY_EXCLUSIVE

(***********************************************************)
(*        SUBROUTINE/FUNCTION DEFINITIONS GO BELOW         *)
(***********************************************************)
(* EXAMPLE: DEFINE_FUNCTION <RETURN_TYPE> <NAME> (<PARAMETERS>) *)
(* EXAMPLE: DEFINE_CALL '<NAME>' (<PARAMETERS>) *)
define_function SendStringRaw(char cParam[]) {
     NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO, dvPort, cParam))
    send_string dvPort,"cParam"
    wait(1) iCommandBusy = false
}

define_function BuildString(integer iIn, integer iLevel) {
    SendStringRaw("itoa(iIn),LEVEL_COMMANDS[iLevel]")
}

define_function Drive() {
    stack_var integer x
    stack_var integer i
    iLoop++
    if (!iCommandBusy) {
    for (x = 1; x <= MAX_OUTPUTS; x++) {
        for (i = 1; i <= MAX_LEVELS; i++) {
        switch (i) {
            case 1: {    //All
            if (iPendingRequired[i][x] && !iCommandBusy) {
                iPendingRequired[i][x] = false
                iPending = false
                if (iOutputRequired[i][x] <> (iOutputActual[2][x] || iOutputActual[3][x])) {
                iCommandBusy = true
                BuildString(iOutputRequired[i][x],i)
                }else {
                iOutputRequired[i][x] = 0
                }
            }
            }
            case 2:     //Video
            case 3: {    //Audio
            if (iPendingRequired[i][x] && !iCommandBusy) {
                iPendingRequired[i][x] = false
                iPending = false
                if (iOutputRequired[i][x] <> iOutputActual[i][x]) {
                iCommandBusy = true
                BuildString(iOutputRequired[i][x],i)
                }else {
                iOutputRequired[i][x] = 0
                }
            }
            }
        }
        }
    }
    }else {
    }

    if (iLoop > 4) {
        iLoop = 1
        if (iCommMode == COMM_MODE_TWO_WAY) {
        SendStringRaw("'I'")    //Sends a heartbeat to check comms
        }
    }
}

define_function Process() {
    stack_var char cTemp[NAV_MAX_BUFFER]
    iSemaphore = true
    while (length_array(cRxBuffer) && NAVContains(cRxBuffer,"NAV_LF")) {
    cTemp = remove_string(cRxBuffer,"NAV_LF",1)
    if (length_array(cTemp)) {
        NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_PARSING_STRING_FROM, dvPort, cTemp))
        cTemp = NAVStripCharsFromRight(cTemp, 2)     //Remove CRLF
        select {
        /*
        active (NAVContains(cTemp,'Qik')): {
            //Manual switch occured, re-check all outputs
            Init()
        }
        */
        active (NAVContains(cTemp,'Chn') && NAVContains(cTemp,'InACT')): {
            //Information Responce
            remove_string(cTemp,'Chn',1)
            iOutputActual[1][1] = atoi(NAVStripCharsFromRight(remove_string(cTemp,' ',1),1))
        }
        /*
        active (NAVContains(cTemp,'Sig')): {
            //Signal Status
            stack_var integer x
            remove_string(cTemp,'Sig',1)
            iNumberOfInputs = (length_array(cTemp) + 1) / 2
            for (x = 1; x <= iNumberOfInputs; x++) {
            if (x == iNumberOfInputs) {
                iInputHasSignal[x] = atoi(cTemp)
            }else {
                iInputHasSignal[x] = atoi(NAVStripCharsFromRight(remove_string(cTemp,' ',1),1))
            }

            send_string vdvObject,"'INPUT_SIGNAL-',itoa(x),',',itoa(iInputHasSignal[x])"
            }
        }
        active (NAVContains(cTemp,'In')): {
            stack_var integer iInput
            stack_var char cLevel[3]
            remove_string(cTemp,'In',1)
            iInput = atoi(NAVStripCharsFromRight(remove_string(cTemp,' ',1),1))
            switch (cTemp) {
            case 'All': {
                iOutputActual[1][1] = iInput
                iOutputActual[2][1] = iInput
                iOutputActual[3][1] = iInput
            }
            case 'Vid': {
                iOutputActual[2][1] = iInput
            }
            case 'Aud': {
                iOutputActual[3][1] = iInput
            }
            }

            //Send back to main source
            send_string vdvObject,"'SWITCH-',itoa(iInput),',',upper_string(cTemp)"
        }
        active (NAVContains(cTemp,'V') && NAVContains(cTemp,'F') && NAVContains(cTemp,'Vmt') && NAVContains(cTemp,'Amt')): {
            stack_var integer iInput
            remove_string(cTemp,'V',1)
            iInput = atoi(NAVStripCharsFromRight(remove_string(cTemp,' ',1),1))
            iOutputActual[1][1] = iInput
            iOutputActual[2][1] = iInput
            iOutputActual[3][1] = iInput
            send_string vdvObject,"'SWITCH-',itoa(iInput),',ALL'"
            send_string vdvObject,"'SWITCH-',itoa(iInput),',VID'"
            send_string vdvObject,"'SWITCH-',itoa(iInput),',AUD'"
        }
        */
        }
    }
    }

    iSemaphore = false
}

define_function TimeOut() {
    cancel_wait 'CommsTimeOut'
    wait 300 'CommsTimeOut' {
    iCommunicating = false
    }
}


define_function Init() {
    //stack_var integer x
    //stack_var char cTemp[NAV_MAX_BUFFER]
    //for (x = 1; x <= MAX_OUTPUTS; x++) { cTemp = "cTemp,itoa(x),'%',itoa(x),'$'" }
    SendStringRaw('I')    //Get current info
}


(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START
create_buffer dvPort,cRxBuffer

iModuleEnabled = true

// Update event tables
rebuild_event()

(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT
data_event[dvPort] {
    online: {
    if (iModuleEnabled) {
        send_command data.device,"'SET MODE DATA'"
        send_command data.device,"'SET BAUD 9600,N,8,1 485 DISABLE'"
        send_command data.device,"'B9MOFF'"
        send_command data.device,"'CHARD-0'"
        send_command data.device,"'CHARDM-0'"
        send_command data.device,"'HSOFF'"
        //SendStringRaw("NAV_ESC,'3CV',NAV_CR")    //Set Verbose Mode to verbose and tagged
        Init()
        timeline_create(TL_DRIVE,ltDrive,length_array(ltDrive),timeline_absolute,timeline_repeat)
    }
    }
    string: {
    if (iModuleEnabled) {
        iCommunicating = true
        [vdvObject,DATA_INITIALIZED] = true
        TimeOut()
         NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_FROM, dvPort, data.text))
        if (!iSemaphore) { Process() }
    }
    }
}

data_event[vdvObject] {
    command: {
    stack_var char cCmdHeader[NAV_MAX_CHARS]
    stack_var char cCmdParam[3][NAV_MAX_CHARS]
    if (iModuleEnabled) {
        NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_COMMAND_FROM, data.device, data.text))
        cCmdHeader = DuetParseCmdHeader(data.text)
        cCmdParam[1] = DuetParseCmdParam(data.text)
        cCmdParam[2] = DuetParseCmdParam(data.text)
        cCmdParam[3] = DuetParseCmdParam(data.text)
        switch (cCmdHeader) {
        case 'PROPERTY': {
            switch (cCmdParam[1]) {
            case 'IP_ADDRESS': {
                //cIPAddress = cCmdParam[2]
                //timeline_create(TL_IP_CHECK,ltIPCheck,length_array(ltIPCheck),timeline_absolute,timeline_repeat)
            }
            case 'ID': {
                //cID = format('%02d',atoi(cCmdParam[2]))
            }
            case 'COMM_MODE': {
                switch (cCmdParam[2]) {
                case 'ONE-WAY': {
                    iCommMode = COMM_MODE_ONE_WAY
                }
                case 'TWO-WAY': {
    			    iCommMode = COMM_MODE_TWO_WAY
				}
			    }
			}
		    }
		}
		case 'PASSTHRU': { SendStringRaw(cCmdParam[1]) }

		case 'SWITCH': {
		    stack_var integer iLevel
		    //iLevel = NAVFindInArrayString(LEVELS,cCmdParam[2])
		    //if (!iLevel) { iLevel = 1 }
		    iOutputRequired[1][1] = atoi(cCmdParam[1])
		    iPendingRequired[1][1] = true
		    iPending = true
		}
	    }
	}
    }
}

timeline_event[TL_DRIVE] { Drive() }

timeline_event[TL_NAV_FEEDBACK] {
    if (iModuleEnabled) {
	if (iNumberOfInputs) {
	    stack_var integer x
	    for (x = 1; x <= iNumberOfInputs; x++) {
		[vdvObject,NAV_INPUT_SIGNAL[x]]	=	(iInputHasSignal[x])
	    }
	}

	if (1) {
	    stack_var integer x
	    for (x = 1; x <= 4; x++) {
		[vdvObject,30 + x]	= (iOutputActual[1][1] == x)
	    }
	}

	[vdvObject,DEVICE_COMMUNICATING] 	= (iCommunicating)
    }
}

(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)
