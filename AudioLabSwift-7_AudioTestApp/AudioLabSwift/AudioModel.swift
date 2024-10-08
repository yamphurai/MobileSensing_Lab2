//  Created by Eric Larson
//  Copyright © 2020 Eric Larson. All rights reserved.

// To manage collection & manipulation of audio data, handle microphone input, compute FFT, and audio playback


import Foundation
import Accelerate

class AudioModel {
    
    // MARK: Private Properties
    private var BUFFER_SIZE:Int    // size of the buffer to store audio data
    var volume:Float = 0.1         // user setable volume
    
    // phase 1, 2 & 3 are initial phases for sine wave generation
    private var phase1:Float = 0.0
    private var phase2:Float = 0.0
    private var phase3:Float = 0.0
    
    // phase increments for since wave generation
    private var phaseIncrement1:Float = 0.0
    private var phaseIncrement2:Float = 0.0
    private var phaseIncrement3:Float = 0.0
    
    private var sineWaveRepeatMax:Float = Float(2*Double.pi)   //max value for phase before it resets
    private var pulseValue:Int = 0     //to track pulse state
    

    // MARK: Public Properties
    var timeData:[Float]                 // array to store time-domain audio data
    var fftData:[Float]                  // array to store fft data of "timeData"
    
    // frequencies for generating sine waves
    var sineFrequency1:Float = 300.0
    var sineFrequency2:Float = 650.0
    var sineFrequency3:Float = 1000.0
    
    var pulsing:Bool = false    // to determine if pulsing effect is active
    
    // property "samplingRate" to get sampling rate from "audioManager"
    lazy var samplingRate:Int = {
        return Int(self.audioManager!.samplingRate)
    }()
    

    
    // MARK: Public Methods
    
    // Initialize "AudioModel" with specific buffer size
    init(buffer_size:Int) {
        BUFFER_SIZE = buffer_size    //size of the frequency buffer
        timeData = Array.init(repeating: 0.0, count: BUFFER_SIZE)   //allocate memory for "timeData" array
        fftData = Array.init(repeating: 0.0, count: BUFFER_SIZE/2)  //allocate memory for "fftData" array
    }
    
    
    // public function for starting processing of microphone data
    func startMicrophoneProcessing(withFps:Double){
        
        // If audioManager is availabe, setup the microphone to copy to circualr buffer
        if let manager = self.audioManager,
            let fileReader = self.fileReader{
            manager.inputBlock = self.handleMicrophone                   //setup microphone input blocks
            manager.outputBlock = self.handleSpeakerQueryWithSinusoids   //setup speaker output blocks
            
            // scheduled timer to update "timeData" and "fftData' at specific Fps
            Timer.scheduledTimer(withTimeInterval: 1.0/withFps, repeats: true) { _ in
                self.runEveryInterval()
            }
            
            // schedule timer to toggle "pulseValue" at specified intervals (every 1/5 = 0.2s) to create pulsing effect
            // periodic change or oscillation in value to create visual effect in user interface
            Timer.scheduledTimer(withTimeInterval: 1.0/5.0, repeats: true) { _ in
                
                self.pulseValue += 1     //increase "pulseValue" by 1 each time the timer fires
                
                //check to see if "pulseValue" is >5
                if self.pulseValue > 5{
                    self.pulseValue = 0   //keeping pulseValue 0-5
                }
            }
            fileReader.play()   //start audio file playback
        }
    }
        
    // method to start audio playback using audioManager
    func play(){
        if let manager = self.audioManager{
            manager.play()
        }
    }
    
    
    // method to stop audio playback using audioManager
    func stop(){
        
        // if audioManager is availabel
        if let manager = self.audioManager{
            manager.pause()            //pause method on manager to pause the audio processing
            
            //set these properties of manager to nil to stop audio input & output processing
            manager.inputBlock = nil
            manager.outputBlock = nil
        }
        
        // if fileReader is available
        if let file = self.fileReader{
            file.pause()  //pause file reading or playback
            file.stop()   //stop file reading or playback
        }
        
        // if there is inputBuffer available
        if let buffer = self.inputBuffer{
            buffer.clear()  //clear the buffer to reset the buffer
        }
        
        // to release resources associated with these objects as they are no longer needed
        inputBuffer = nil
        fftHelper = nil
        fileReader = nil
    }
    
    
    //==========================================
    // MARK: Private Properties
    
    // to manager audio input and output
    private lazy var audioManager:Novocaine? = {
        return Novocaine.audioManager()
    }()
    
    // performs FFT calculations
    private lazy var fftHelper:FFTHelper? = {
        return FFTHelper.init(fftSize: Int32(BUFFER_SIZE))
    }()
    
    
    // to store audio data in a circular buffer
    private lazy var inputBuffer:CircularBuffer? = {
        return CircularBuffer.init(numChannels: Int64(self.audioManager!.numInputChannels),
                                   andBufferSize: Int64(BUFFER_SIZE))
    }()
    
    
    // to read audio data from a file
    private lazy var fileReader:AudioFileReader? = {
            
            // find song "satisfaction" in the main Bundle
            if let url = Bundle.main.url(forResource: "satisfaction", withExtension: "mp3"){
                // if we could find the url for the song in main bundle, setup file reader
                // the file reader is doing a lot here becasue its a decoder
                // so when it decodes the compressed mp3, it needs to know how many samples
                // the speaker is expecting and how many output channels the speaker has (mono, left/right, surround, etc.)
                var tmpFileReader:AudioFileReader? = AudioFileReader.init(audioFileURL: url,
                                                       samplingRate: Float(audioManager!.samplingRate),
                                                       numChannels: audioManager!.numOutputChannels)
                
                tmpFileReader!.currentTime = 0.0 // start from time zero!
                
                return tmpFileReader
            }else{
                print("Could not initialize audio input file")
                return nil
            }
        }()
    
    
    
    //==========================================
    // MARK: Model Callback Methods
    
    
    // method to process audio data from input data to perform FFT on them converting time-domain data to frequency-domain data
    private func runEveryInterval(){
        
        // if the input buffer is available
        if inputBuffer != nil {
            self.inputBuffer!.fetchFreshData(&timeData, withNumSamples: Int64(BUFFER_SIZE))  //copy fresh time-domain data to "timeData" array
            fftHelper!.performForwardFFT(withData: &timeData, andCopydBMagnitudeToBuffer: &fftData) // perform FFT on timeData and store them in fftData
        }
    }
    
    
    //==========================================
    // MARK: Audiocard Callbacks
    
    // handle audio data received from  mic using parameters data, numFrames, and numChannels
    private func handleMicrophone (data:Optional<UnsafeMutablePointer<Float>>, numFrames:UInt32, numChannels: UInt32) {
        self.inputBuffer?.addNewFloatData(data, withNumSamples: Int64(numFrames))  // copy samples from the microphone into circular buffer
    }
    
    
    // handle audio data sent to the speaker. Adds synthesized sine wave signals to audio output ("data") & modulates them based on certain conditions
    private func handleSpeakerQueryWithSinusoids(data:Optional<UnsafeMutablePointer<Float>>, numFrames:UInt32, numChannels: UInt32){
            
        
        // if output audio data is "data" and audioManger is "manager"
        if let arrayData = data, let manager = self.audioManager{
                
                var addFreq:Float = 0  // additional frequency variable (additional frequency component added to base frequency)
                var mult:Float = 1.0   // multiplication factor variable
            
                // if pulsing is active & pulseValue is 1
            if pulsing && pulseValue==1{
                addFreq = 1000.0
                // if pulsing is active & pulseValue is > 1
                }else if pulsing && pulseValue > 1{
                    mult = 0.0
                }
                
                // if there is a file reader
                if let file = self.fileReader{
                    
                    // get fresh samples from audio file & store them in "arrayData" array by reference
                    file.retrieveFreshAudio(arrayData,
                                numFrames: numFrames,
                                numChannels: numChannels)
                    
                    // adjust volume of audio file output
                    var volume:Float = mult*0.15
                    
                    vDSP_vsmul(arrayData, 1, &(volume), arrayData, 1, vDSP_Length(numFrames*numChannels))  //multiply each element in "arrayData" by volume
                }
                
            
                // compute phase increments per sample for generating sine waves at specified frequency
                phaseIncrement1 = Float(2*Double.pi*Double(sineFrequency1+addFreq)/manager.samplingRate)
                phaseIncrement2 = Float(2*Double.pi*Double(sineFrequency2+addFreq)/manager.samplingRate)
                phaseIncrement3 = Float(2*Double.pi*Double(sineFrequency3+addFreq)/manager.samplingRate)
                
                // to generate sine waves and add audio data
                var i = 0     // loop counter
                let chan = Int(numChannels)   // number of channels
                let frame = Int(numFrames)    // number of frames
            
                // if the audio is mono or single channel
                if chan==1{
                    
                    //loop throgh eah frame
                    while i<frame{
                        
                        // add to arrayData: sum of three sine waves that are moduleted by corresponding phases & amplitudes
                        arrayData[i] += (0.9*sin(phase1)+0.4*sin(phase2)+0.1*sin(phase3))*mult
                        
                        // increment of phases
                        phase1 += phaseIncrement1
                        phase2 += phaseIncrement2
                        phase3 += phaseIncrement3
                        
                        // if a phase value exceeds "sineWaveRepeatMax", repeat next cycle since sine wave completed one cycle
                        if (phase1 >= sineWaveRepeatMax) { phase1 -= sineWaveRepeatMax }
                        if (phase2 >= sineWaveRepeatMax) { phase2 -= sineWaveRepeatMax }
                        if (phase3 >= sineWaveRepeatMax) { phase3 -= sineWaveRepeatMax }
                        i+=1
                    }
                    
                // if the aduio is
                }else if chan==2{
                    
                    // length is frames X channels
                    let len = frame*chan
                    
                    // if i is less than length
                    while i<len{
                        
                        // add to arrayData: sum of three sine waves that are moduleted by corresponding phases & amplitudes
                        arrayData[i] += (0.9*sin(phase1)+0.4*sin(phase2)+0.1*sin(phase3))*mult
                        arrayData[i+1] = arrayData[i]
                        
                        // increment of phases
                        phase1 += phaseIncrement1
                        phase2 += phaseIncrement2
                        phase3 += phaseIncrement3
                        
                        // if a phase value exceeds "sineWaveRepeatMax", repeat next cycle since sine wave completed one cycle
                        if (phase1 >= sineWaveRepeatMax) { phase1 -= sineWaveRepeatMax }
                        if (phase2 >= sineWaveRepeatMax) { phase2 -= sineWaveRepeatMax }
                        if (phase3 >= sineWaveRepeatMax) { phase3 -= sineWaveRepeatMax }
                        i+=2
                    }
                }
                
            }
        }
    
    //==========================================
    // MARK: Added From Class Example To Generate Sound For Doppler
    
    func startProcessingSinewaveForPlayback(withFreq:Float=330.0){
        sineFrequency = withFreq
        if let manager = self.audioManager{
            // swift sine wave loop creation
            manager.outputBlock = self.handleSpeakerQueryWithSinusoid
        }
    }
    
    var sineFrequency:Float = 0.0 { // frequency in Hz (changeable by user)
            didSet{
                if let manager = self.audioManager {
                    // if using swift for generating the sine wave: when changed, we need to update our increment
                    phaseIncrement = Float(2*Double.pi*Double(sineFrequency)/manager.samplingRate)
                }
            }
        }
    
    // SWIFT SINE WAVE
    // everything below here is for the swift implementation
    private var phase:Float = 0.0
    private var phaseIncrement:Float = 0.0
    
    private func handleSpeakerQueryWithSinusoid(data:Optional<UnsafeMutablePointer<Float>>, numFrames:UInt32, numChannels: UInt32){
        // while pretty fast, this loop is still not quite as fast as
        // writing the code in c, so I placed a function in Novocaine to do it for you
        // use setOutputBlockToPlaySineWave() in Novocaine
        // EDIT: fixed in 2023
        if let arrayData = data{
            var i = 0
            let chan = Int(numChannels)
            let frame = Int(numFrames)
            if chan==1{
                while i<frame{
                    arrayData[i] = sin(phase)
                    phase += phaseIncrement
                    if (phase >= sineWaveRepeatMax) { phase -= sineWaveRepeatMax }
                    i+=1
                }
            }else if chan==2{
                let len = frame*chan
                while i<len{
                    arrayData[i] = sin(phase)
                    arrayData[i+1] = arrayData[i]
                    phase += phaseIncrement
                    if (phase >= sineWaveRepeatMax) { phase -= sineWaveRepeatMax }
                    i+=2
                }
            }
            // adjust volume of audio file output
            vDSP_vsmul(arrayData, 1, &(self.volume), arrayData, 1, vDSP_Length(numFrames*numChannels))
                            
        }
    }
}
