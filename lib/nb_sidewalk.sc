// sidewalk v1.0 @sonoCircuit
// based on passersby v1.2.0 @markeats (thank you!)

NB_sidewalk {

	*initClass {

		var synthParams, synthGroup, synthVoices;
		var synthMod, modBus, numModDest = 8;
		var numVoices = 6;

		synthParams = Dictionary.newFrom([
			\lastFreq, 220,
			\pitchBend, 1,
			\glide, 0,
			\amp, 0.8,
			\pan, 0,
			\panDrift, 0,
			\sendA, 0,
			\sendB, 0,
			\fm1Ratio, 0.66,
			\fm2Ratio, 3.3,
			\fm1Index, 0,
			\fm2Index, 0,
			\timbre, 0,
			\waveShape, 0,
			\waveFolds, 0,
			\lpfHz, 10000,
			\envType, 0,
			\attack, 0.04,
			\decay, 0.8
		]);

		StartUp.add {

			var s = Server.default;

			synthVoices = Array.newClear(numVoices);

			OSCFunc.new({ |msg|
				if (synthGroup.isNil) {

					Routine.new({

						// add synthdefs
						SynthDef(\sidewalkMod, {

							arg outBus,
							lfoShape = 0, lfoFreq = 0.5, lfoDrift = 0, lfoFreqMod = 0, lfoDriftMod = 0, modDepth = 0,
							lpfHzLfo = 0, shapeLfo = 0, foldLfo = 0, fm1Lfo = 0, fm2Lfo = 0, panLfo = 0,
							lpfHzMod = 0, shapeMod = 0, foldMod = 0, fm1Mod = 0, fm2Mod = 0, sendAMod = 0, sendBMod = 0;

							var lfoSrc, modSrc;
							var lfoHzMul = 20, lfoHzMax = 40;

							// lfo freq modulation
							lfoDrift = (lfoDrift + (lfoDriftMod * modDepth)).clip(0, 1);
							lfoDrift = LFNoise0.kr(0.22 * (1 + (lfoDrift * 12))) * lfoDrift * lfoHzMul;
							lfoFreq = (lfoFreq + lfoDrift + (lfoFreqMod * modDepth * lfoHzMul)).clip(0.01, lfoHzMax);

							// lfos
							lfoSrc = Select.kr(lfoShape, [
								LFTri.kr(lfoFreq),
								LFSaw.kr(lfoFreq),
								LFPulse.kr(lfoFreq),
								LFDNoise0.kr(lfoFreq * 2)
							]);

							// scale
							modSrc = Array.fill(numModDest, 0);
							modSrc[0] = (lfoSrc * lpfHzLfo * 24) + (lpfHzMod * modDepth * 12);
							modSrc[1] = (lfoSrc * shapeLfo) + (shapeMod * modDepth);
							modSrc[2] = (lfoSrc * foldLfo * 2) + (foldMod * modDepth);
							modSrc[3] = (lfoSrc * fm1Lfo * 0.5) + (fm1Mod * modDepth);
							modSrc[4] = (lfoSrc * fm2Lfo * 0.5) + (fm2Mod * modDepth);
							modSrc[5] = lfoSrc * panLfo * 0.8;
							modSrc[6] = sendAMod * modDepth;
							modSrc[7] = sendBMod * modDepth;

							Out.kr(outBus, modSrc);
						}).add;

						SynthDef(\sidewalkSynth,{
							arg out, sendABus, sendBBus, ctrlBus,
							amp = 1, vel = 0.7, sendA = 0, sendB = 0, pan = 0, panDrift = 0,
							freq = 220, lastFreq = 220, pitchBend = 1, bendDepth = 0,
							glide = 0, waveShape = 0, waveFolds = 0,
							fm1Ratio = 0.66, fm2Ratio = 3.3, fm1Index = 0, fm2Index = 0,
							envType = 0, gate = 1, attack = 0.04, decay = 1, lpfHz = 10000;

							var signal, width, gain, att, modSrc,
							modFreq, mod1, mod2, mod1Freq, mod2Freq,
							filterEnvVel, filterEnvLow, lpfFreq,
							lpgFltEnv, lpgAmpEnv, asrFltEnv, asrAmpEnv, fltEnv, ampEnv, dA;

							var cLag = 0.005, foldCeil = 0.5;

							// lfo in
							modSrc = In.kr(ctrlBus, numModDest);

							// smooth, modulate, clamp
							freq = XLine.kr(lastFreq, freq, glide);
							freq = (freq * (pitchBend * bendDepth).midiratio).clip(20, 20000);

							lpfHz = Lag.kr(lpfHz * modSrc[0].midiratio, cLag).clip(100, 10000);
							waveShape = Lag.kr(waveShape + modSrc[1], cLag).clip(0, 1);
							waveFolds = Lag.kr(waveFolds + modSrc[2], cLag).clip(0, 3);
							fm1Index = Lag.kr((fm1Index + modSrc[3]).squared, cLag).clip(0, 1);
							fm2Index = Lag.kr((fm2Index + modSrc[4]).squared, cLag).clip(0, 1);
							pan = Lag.kr(pan + modSrc[5] + (panDrift * Rand(-0.8, 0.8)), 0.4).clip(-1, 1);
							sendA = Lag.kr(sendA + modSrc[6], cLag).clip(0, 1);
							sendB = Lag.kr(sendB + modSrc[7], cLag).clip(0, 1);

							fm1Ratio = Lag.kr(fm1Ratio, cLag);
							fm2Ratio = Lag.kr(fm2Ratio, cLag);

							attack = attack.clip(0.003, 8);
							decay = decay.clip(0.01, 10);
							vel = vel.linlin(0, 1, 0.2, 1);

							// envelopes
							dA = Select.kr(envType, [2, 0]);

							lpgFltEnv = EnvGen.ar(Env.new([0, 1, 0], [0.003, decay], [4, -20]), gate);
							lpgAmpEnv = EnvGen.ar(Env.new([0, 1, 0], [0.002, decay], [4, -10]), gate, doneAction: dA);

							asrFltEnv = EnvGen.ar(Env.new([0, 1, 0], [attack, decay], -4, 1), gate);
							asrAmpEnv = EnvGen.ar(Env.asr(attack, 1, decay), gate, doneAction: (2 - dA));

							fltEnv = Select.kr(envType, [lpgFltEnv, asrFltEnv]);
							ampEnv = Select.kr(envType, [lpgAmpEnv, asrAmpEnv]);

							// modulators
							mod1Freq = freq * fm1Ratio * LFNoise2.kr(0.1, 0.001, 1);
							mod1 = SinOsc.ar(mod1Freq, 0, fm1Index * 22 * mod1Freq);
							mod2Freq = freq * fm2Ratio * LFNoise2.kr(0.1, 0.005, 1);
							mod2 = SinOsc.ar(mod2Freq, 0, fm2Index * 12 * mod2Freq);
							modFreq = freq + mod1 + mod2;

							// osc -> a sloppy var waveshape
							width = waveShape.linlin(0.5, 1, 0.5, 0.04);
							gain = waveShape.lincurve(0, 0.5, 24, 1, -3.6);
							att = gain.lincurve(1, 24, 1, 0.5, -15.8);
							signal = tanh(VarSaw.ar(modFreq, width/2, width, foldCeil) * gain).softclip * att;

							// fold
							signal = Fold.ar(signal * (1 + (waveFolds * 2)), foldCeil.neg, foldCeil);

							// hack away some aliasing
							signal = LPF.ar(signal, 12000);

							// add noise
							signal = signal + (PinkNoise.ar * -50.dbamp);

							// filter
							filterEnvVel = vel.linlin(0, 1, 0.5, 1);
							filterEnvLow = (lpfHz * filterEnvVel).clip(20, 300);
							lpfFreq = fltEnv.linlin(0, 1, filterEnvLow, lpfHz * filterEnvVel);
							signal = RLPF.ar(signal, lpfFreq, 0.9);
							signal = RLPF.ar(signal, lpfFreq, 0.9) * ampEnv;

							// saturation amp
							signal = tanh(signal * vel * amp * 3.dbamp).softclip * -6.dbamp;
							// pan
							signal = Pan2.ar(signal, pan);

							Out.ar(sendABus, sendA * signal);
							Out.ar(sendBBus, sendB * signal);
							Out.ar(out, signal);
						}).add;

						// wait
						s.sync;

						// add group and control bus
						synthGroup = Group.new(s);
						modBus = Bus.control(s, numModDest);
						synthMod = nil;

						"nb sidewalk initialized".postln;

					}).play;

				};
			}, "/nb_sidewalk/init");

			OSCFunc.new({ |msg|
				if (synthMod.isNil) {
					synthMod = Synth(\sidewalkMod, [\outBus, modBus], s);
					"nb sidewalk init modulation".postln
				};
			}, "/nb_sidewalk/init_mod");

			OSCFunc.new({ |msg|
				if (synthMod.notNil) {
					synthMod.free;
					synthMod = nil;
					"nb sidewalk free modulation".postln
				};
			}, "/nb_sidewalk/free_mod");

			OSCFunc.new({ |msg|
				var vox = msg[1].asInteger;
				var freq = msg[2].asFloat;
				var vel = msg[3].asFloat;
				var syn;
				if (synthGroup.notNil) {
					if (synthVoices[vox].notNil) { synthVoices[vox].set(\gate, -1.05) };
					syn = Synth.new(\sidewalkSynth,
						[
							\freq, freq,
							\vel, vel,
							\ctrlBus, modBus,
							\sendABus, ~sendA ? s.outputBus,
							\sendBBus, ~sendB ? s.outputBus,
						] ++ synthParams.getPairs, target: synthGroup
					);
					synthVoices[vox] = syn;
					syn.onFree({ if(synthVoices[vox] === syn) {synthVoices[vox] = nil} });
					synthParams[\lastFreq] = freq;
				};
			}, "/nb_sidewalk/note_on");

			OSCFunc.new({ |msg|
				var vox = msg[1].asInteger;
				if (synthVoices[vox].notNil) { synthVoices[vox].set(\gate, 0) };
			}, "/nb_sidewalk/note_off");

			OSCFunc.new({ |msg|
				var key = msg[1].asSymbol;
				var val = msg[2].asFloat;
				if (synthGroup.notNil) {
					synthGroup.set(key, val);
				};
				synthParams[key] = val;
			}, "/nb_sidewalk/set_param");

			OSCFunc.new({ |msg|
				var key = msg[1].asSymbol;
				var val = msg[2].asFloat;
				if (synthGroup.notNil) {
					synthMod.set(key, val);
				};
				synthParams[key] = val;
			}, "/nb_sidewalk/set_mod");

			OSCFunc.new({ |msg|
				if (synthGroup.notNil) {
					synthGroup.set(\gate, -1.05);
				};
			}, "/nb_sidewalk/panic");

			OSCFunc.new({ |msg|
				if (synthGroup.notNil) {
					synthGroup.free;
					synthMod.free;
					modBus.free;
					synthGroup = nil;
					synthMod = nil;
					numVoices.do({ arg vox;
						synthVoices[vox] = nil
					});
					"nb sidewalk removed".postln;
				};
			}, "/nb_sidewalk/free");

		}
	}
}
