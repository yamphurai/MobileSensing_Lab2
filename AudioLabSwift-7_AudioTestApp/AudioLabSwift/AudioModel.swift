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
    
    
    // MARK: Public Properties
    var timeData:[Float]                 // array to store time-domain audio data
    var fftData:[Float]                  // array to store fft data of "timeData"
    private var lookback:Int
    
    
    private var weights:[Float]
    private var weightsSum:Float
    private var prevMaxTimeData:[Float] = []
    
    var frozenFftData:[Float]
    var frozenTimeData:[Float]
    var peak1Freq:Float = 0.0
    var peak2Freq:Float = 0.0
    // frequencies for generating sine waves
    var sineFrequency1:Float = 300.0
    var sineFrequency2:Float = 650.0
    var sineFrequency3:Float = 1000.0
    var result:String;
    
    var pulsing:Bool = false    // to determine if pulsing effect is active
    
    // property "samplingRate" to get sampling rate from "audioManager"
    lazy var samplingRate:Int = {
        return Int(self.audioManager!.samplingRate)
    }()
    
    
    private func weightFunc(x:Float,numVals:Int) -> Float{
        //        return Float(((-1 * x) + numVals)/Float(numVals))
        return ((-1 * x) + Float(numVals + 1)) / Float(numVals + 1)
    }
    
    // MARK: Public Methods
    
    // Initialize "AudioModel" with specific buffer size
    init(buffer_size:Int,lookback:Int) {
        BUFFER_SIZE = buffer_size    //size of the frequency buffer
        timeData = Array.init(repeating: 0.0, count: BUFFER_SIZE)   //allocate memory for "timeData" array
        fftData = Array.init(repeating: 0.0, count: BUFFER_SIZE/2)  //allocate memory for "fftData" array
        weights = []
        weightsSum = 0
        frozenFftData = []
        frozenTimeData = []
        result = "";

        self.lookback = lookback
        for i in 1...lookback {
            let wt = weightFunc(x: Float(i),numVals: lookback)
            weights.append(wt)
            weightsSum += wt
        }
    }
    
    
    // public function for starting processing of microphone data
    func startMicrophoneProcessing(withFps:Double){
        
        // If audioManager is availabe, setup the microphone to copy to circualr buffer
        if let manager = self.audioManager {
            manager.inputBlock = self.handleMicrophone
            
            // Repeat FPS Times / Second Using Timer Class
            Timer.scheduledTimer(withTimeInterval: 1.0 / withFps, repeats: true) { _ in
                self.runEveryInterval()
            }
        
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
    
    public func calcLoudestSounds(windowSize:Int=3){
        var freqRes:Float = -10.0
        var peakLookup = Dictionary<Float, Int>(minimumCapacity: frozenFftData.count)
        
        var peaks:[Float] = []
        freqRes = Float((self.audioManager?.samplingRate)!) / Float(self.BUFFER_SIZE)
        for i in 0...(frozenFftData.count - windowSize) {
            var maxValue:Float = 0.0
            vDSP_maxv(&frozenFftData + i, 1, &maxValue, vDSP_Length(windowSize))
            
            if maxValue == frozenFftData[i + Int(windowSize/2)] {
                peaks.append(maxValue)
                peakLookup[maxValue] = i
            }
        }
        
        var peak1:Float = 0.0
        vDSP_maxv(peaks, 1, &peak1, vDSP_Length(peaks.count))
        let peak1Loc = peakLookup[peak1]
        peaks = peaks.filter { $0 != peak1 }
        
        var peak2:Float = 0.0
        vDSP_maxv(peaks, 1, &peak2, vDSP_Length(peaks.count))
        let peak2Loc = peakLookup[peak2]
        
        self.peak1Freq = quadraticApprox(peakLocation: peak1Loc!, deltaF: freqRes)
        self.peak2Freq = quadraticApprox(peakLocation: peak2Loc!, deltaF: freqRes)
        
    }

    
    private func quadraticApprox(peakLocation:Int,deltaF:Float) -> Float {
        let m1 = frozenFftData[peakLocation-1]
        let m2 = frozenFftData[peakLocation]
        let m3 = frozenFftData[peakLocation + 1]
        
        let f2 = Float(peakLocation) * deltaF
        
        return f2 + ((m1-m2)/(m3 - 2 * m2 + m1)) * (deltaF / 2.0)
    }
    ///Check if a sufficiently large sound was detected by the microphone (above a certain float threshold for average sin wave)
    public func isLoudSound(cutoff:Float) -> Bool {
        var maxTimeVal:Float = 0.0
        vDSP_maxv(timeData, 1, &maxTimeVal, vDSP_Length(timeData.count))
        var isTrue = false
        var weightedTimeVals:[Float] = prevMaxTimeData
        vDSP_vmul(prevMaxTimeData, 1, weights, 1, &weightedTimeVals, 1, vDSP_Length(prevMaxTimeData.count))
        let wtAvg = vDSP.sum(weightedTimeVals) / weightsSum
    
        let pctDiff = (maxTimeVal - wtAvg) / wtAvg
        
        
        if pctDiff > cutoff {
            isTrue = true
            self.frozenFftData = fftData
            self.frozenTimeData = timeData
        }
        prevMaxTimeData.insert(maxTimeVal, at: 0)
        if prevMaxTimeData.count > self.lookback {
            prevMaxTimeData.popLast()
        }
        
        return isTrue
    }
    
    public func determineVowel() {
           let magnitudeDifference = peak1Freq - peak2Freq

           // Thresholds for vowel detection
           let thresholdForOoooo: Float = 5.0 // Adjust based on testing
           let thresholdForAhhhh: Float = 2.0 // Adjust based on testing

           if magnitudeDifference > thresholdForOoooo {
               result = "Detected sound: ooooo"
           } else {
               result = "Detected sound: ahhhh"
           }
       }
    
    func pause(){
        self.audioManager?.pause()
    }
    
}
