Module A
Create an iOS ViewController (as part of an app) using the example template that:

Reads from the microphone
Takes an FFT of the incoming audio stream
Displays the frequency of the two loudest tones within (+-3Hz) accuracy 
This can be done by displaying the two frequencies as UILabels on the view. These labels will update rapidly, and will show "noise" when frequencies are not playing. Your app should only display the frequencies when they are of large enough magnitude. That is, have a way to "lock in" the last frequencies of large magnitude detected on the display. If no large magnitude frequencies are detected, the UILabels will not update. 
Is able to distinguish tones at least 50Hz apart, lasting for 200ms or more (think critically about this constraint in terms of buffer size, FFT size, and windows for finding maxima)
The main aspect of this portion is creating and documenting an algorithm that can perform this "peak finding" for two tones. 
Exceptional Credit required for 7000 level students): Detect the difference between "ooooo" and "ahhhh" vowel sounds using the largest two frequencies. Display if the sound is "ooooo" or "ahhhh"  as a separate UILabel.
5000 Level students: You have free rein to decide what to do for exceptional credit. 
Verify the functionality of the application by taking of video of the app working. The sound source must be external to the phone (i.e., laptop, instrument, another phone, etc.). There is an audio test app available for playing different sine waves. Please look at the branch names "7_AudioTestApp" for the "AudioLabSwift" GitHub project: https://github.com/SMU-MSLC/AudioLabSwift/tree/7_AudioTestAppLinks to an external site.

Module B
Create an iOS ViewController (as part of an app) that:

Reads from the microphone
Plays a settable (via a slider or setter control) inaudible tone to the speakers (17-20kHz)
Displays the magnitude of the FFT (in dB) zoomed into the peak that is playing (this is mostly done in the example AudioLabSwift project). 
Is able to distinguish when the user is {not gesturing, gestures toward, or gesturing away} from the microphone using Doppler shifts in the frequency. 
The main aspect of this portion is creating and documenting an algorithm that can detect these doppler shifts reliably. 

Turn in:

the source code for your app in zipped format or via GitHub. (Upload as "teamNameAssignmentTwo.zip".) Use proper coding techniques and naming conventions for all programming languages.
Your team member names should appear somewhere in the Xcode project. 
A video of your app working as intended and description of its functionality.
