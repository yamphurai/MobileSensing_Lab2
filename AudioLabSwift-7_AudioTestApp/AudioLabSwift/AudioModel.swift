//  Created by Eric Larson
//  Copyright © 2020 Eric Larson. All rights reserved.

// To manage collection & manipulation of audio data, handle microphone input, compute FFT, and audio playback

import Foundation
import Accelerate

class AudioModel {
    
    // MARK: Private Properties
    private var BUFFER_SIZE:Int    // size of the buffer to store audio data
    
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
    private var samplesProcessed: Int = 0   //Check: keep track of audio samples processed
    
    
    //Check: release resources related to microphone if needed
    func stopMicrophoneInput() {
        if let manager = self.audioManager {
            manager.pause() // Pause the audio manager
            manager.inputBlock = nil // Clear the input block
            manager.outputBlock = nil // Clear the output block
        }
        // Optionally, you can also clear the input buffer if needed
        if let buffer = self.inputBuffer {
            buffer.clear()
        }
        inputBuffer = nil
        fftHelper = nil // Clear FFT helper if needed
        samplesProcessed = 0 // Reset the counter
    }
    
    
    // MARK: Public Properties
    var timeData:[Float]                 // array to store time-domain audio data
    var fftData:[Float]                  // array to store fft data of "timeData"
    
    // frequencies for generating sine waves
    var sineFrequency1:Float = 300.0
    var sineFrequency2:Float = 650.0
    var sineFrequency3:Float = 1000.0
    
    var pulsing:Bool = false    // to determine if pulsing effect is active
    
    // MARK: SamplingRate
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
        if let manager = self.audioManager {
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
        }
    }
    
    func play(){
        if let manager = self.audioManager{
            manager.play()
        }
    }
    
    func stop(){
        
        // if audioManager is availabel
        if let manager = self.audioManager{
            manager.pause()
            
            //set these properties of manager to nil to stop audio input & output processing
            manager.inputBlock = nil
            manager.outputBlock = nil
        }
        
        stopMicrophoneInput()   //stop microphone input and processing
        
        // if there is inputBuffer available
        if let buffer = self.inputBuffer{
            buffer.clear()  //clear the buffer to reset the buffer
        }
        
        // to release resources associated with these objects as they are no longer needed
        inputBuffer = nil
        fftHelper = nil
        samplesProcessed = 0  //Module A: reset the counter
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
        return CircularBuffer.init(numChannels: Int64(self.audioManager!.numInputChannels), andBufferSize: Int64(BUFFER_SIZE))
    }()

    //==========================================
    // MARK: Model Callback Methods
    
    
    // method to process audio data from input data to perform FFT on them converting time-domain data to frequency-domain data
    private func runEveryInterval(){
        
        // if the input buffer is available
        if inputBuffer != nil {
            self.inputBuffer!.fetchFreshData(&timeData, withNumSamples: Int64(BUFFER_SIZE))  //copy fresh time-domain data to "timeData" array
            print("Raw audio data: \(timeData.prefix(100))") // Check: Print first 100 samples
            fftHelper!.performForwardFFT(withData: &timeData, andCopydBMagnitudeToBuffer: &fftData) // perform FFT on timeData and store them in fftData
            print("FFT Data (raw magnitudes): \(fftData.prefix(100))")    // Check: Print first 100 FFT magnitudes
            
            addFFTDataToHistory(fftData) //Module A:FFT data to history
            detectLoudestFrequencies()  //Module A: detect loudest frequencies
            
            printFrequencies() //check
            samplesProcessed += 1  //Check: counter for frequency samples processed
            
            /* Check: stop processing after 100 audio samples
            if samplesProcessed >= 100 {
                stopMicrophoneInput()
            }
             */
        }
    }
    
    // Module A
    private var historySize = 50    // number of fft frames to keep in history ensuring to have enough data for temporary analysis
    private var fftHistory: [[Float]] = []  // array to store fft data for last historySize frames
    
    // Module A: Method to add new FFT data to the history
    private func addFFTDataToHistory(_ fftData: [Float]) {
        
        // if history is full, remove oldest entry for new data
        if fftHistory.count >= historySize {
            fftHistory.removeFirst()
        }
        fftHistory.append(fftData)  //add the fft data to the history
    }
    
    // Module A: Method to detect the two loudest frequencies that meet the criteria
    func detectLoudestFrequencies() -> (Float, Float)? {
        
        // if we have enough frames in history
        guard fftHistory.count == historySize else {
            return nil  //if not enough frames
        }
        
        var frequencyMagnitudes: [Float: Float] = [:]  // Dictionaries to store frequency magnitudes & counts across frames
        
        // Iterate over each frame in the history
        for frame in fftHistory {
            for (index, magnitude) in frame.enumerated() {
                let frequency = Float(index) * Float(samplingRate) / Float(BUFFER_SIZE)
                
                // Update the maximum magnitude for each frequency
                if let existingMagnitude = frequencyMagnitudes[frequency] {
                    frequencyMagnitudes[frequency] = max(existingMagnitude, magnitude)
                } else {
                    frequencyMagnitudes[frequency] = magnitude
                }
            }
        }
        
        // Find the two frequencies with the highest magnitudes
        let sortedFrequencies = frequencyMagnitudes.keys.sorted { frequencyMagnitudes[$0]! > frequencyMagnitudes[$1]! }
        var selectedFrequencies: [Float] = []  //store the selected frequencies
        
        // go through sorted frequencies to find the two loudest frequencies
        for frequency in sortedFrequencies {
            if selectedFrequencies.isEmpty {
                selectedFrequencies.append(frequency)
            } else if selectedFrequencies.allSatisfy({ abs($0 - frequency) >= 50 }) {
                selectedFrequencies.append(frequency)
            }
            
            if selectedFrequencies.count == 2 {
                print("Loudest Frequencies: \(selectedFrequencies[0]) Hz, \(selectedFrequencies[1]) Hz")
                return (selectedFrequencies[0], selectedFrequencies[1])
            }
        }
        return nil //if not enough frequencies found
    }
    
    
    // Check
    private func printFrequencies() {
        // Print the first few frequencies in the fftData
        for i in 0..<min(10, fftData.count) {
            let frequency = Float(i) * Float(samplingRate) / Float(BUFFER_SIZE)
            print("Frequency: \(frequency) Hz, Amplitude: \(fftData[i])")
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
            
            let volume: Float = mult * 0.15  // volume adjustment for microphone input
            
            // Apply the volume to each channel in the arrayData
            for i in 0..<Int(numFrames) {
                arrayData[i * Int(numChannels)] *= volume // Apply to channel 0
                if numChannels > 1 {
                    arrayData[i * Int(numChannels) + 1] *= volume // Apply to channel 1
                }
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
            }else if chan==2{
                let len = frame*chan  // length is frames X channels
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
    
    /* to read audio data from a file
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
     */

}
    
