using Toybox.WatchUi as Ui;
using Toybox.Math;
using Toybox.System as Sys;
using Toybox.Activity as Activity;
using Toybox.Application as App;
using Toybox.Application.Properties as Props;
using Toybox.FitContributor;
using Toybox.Attention;

//using Toybox.Test;

enum {
	TIMER_STATE_OFF,
	TIMER_STATE_STOPPED,
	TIMER_STATE_PAUSED,
	TIMER_STATE_ON
}

const cDistAverageOver = "100.0"; // Distance (m) over which to average Rate
const cTimeAverageOver = 60; // Time (s) over which to average Rate

(:smallMem)
const bufLen = 350; // max number of points

(:largeMem)
const bufLen = 1000; // max number of points

const cShowPace = true;
const cUseDist = true;
const cUseOpposite = false;
const cRecordData = false;
const cInvertData = false;
const cZoneCheck = false;

const KM_PER_MILE = 1.609344; // km in a mile
const METRES_PER_MILE = 1609.344; // metres in a mile
//const MILES_PER_METER = 0.000621371; // Reciprocal of above
const METRES_PER_YARD = 0.9144;

const PACE0_SPEED_FIELD_ID = 0;

class RollingAverageView extends Ui.SimpleDataField {

hidden var mZoneCheck = false;
hidden var mUpperLimitPace = null;
hidden var mLowerLimitPace = null;
hidden var mUpperLimitSpeed = null;
hidden var mLowerLimitSpeed = null;
hidden var mDoVibe = 0;
hidden var mVibe;

	hidden var mNotMetricPace = false;  // ie they are Sys.UNIT_METRIC by default
	hidden var mNotMetricDist = false;  // ie they are Sys.UNIT_METRIC by default

	hidden var mUseDist = true;
	hidden var mAverageOver = 100; // Distance (m) or Time (s) over which to average Rate
	hidden var mShowAsPace = true;

	hidden var mRecordData = false;
	hidden var mInvertData = false;

    hidden var mTimerState = TIMER_STATE_OFF;

	hidden var mTimes = new [bufLen];
	hidden var mDists = new [bufLen];

    hidden var mJustStarted = true;
    hidden var mOldest  = 0;
    hidden var mCurrent = 0;

    hidden var mSlow = false; // true do compute every "Mod" calls, false do it every time
    hidden var mMod = 1; // a toggle
    hidden var mDoCompute = 0; // a toggle

    hidden var mNotSupported = false;
    hidden var mVal	  = "";
    hidden var mRate  = 0.0;

    hidden var FitPaceField = null;

    // Set the label of the data field here.
    function initialize() {
		var tAverageOver;
		var tiAverageOver;
		var tfAverageOver;
		var tDistTime;
		var tUnits;
		var tShowAsPace;
		var tUseOpposite;
		var mUseOpposite;
		var tRecordData;
		var tInvertData;
		var tZoneCheck;

        SimpleDataField.initialize();

// Check whether this device can actually get the required info and if it's worth going any further
		var info = Activity.getActivityInfo();
       	if (!(info has :timerTime) || !(info has :elapsedDistance)) {
       		label = "Rolling Average";
       		mNotSupported = true;
       		return;
       	}

        mTimes[0] = 0;
        mDists[0] = 0;

		if ( App has :Properties ) {
	        tDistTime = Props.getValue("distTime");
        	tAverageOver = Props.getValue("averageOver");
	        tShowAsPace = Props.getValue("showPace");
	        tUseOpposite = Props.getValue("useOpposite");
	        tRecordData = Props.getValue("recordData");
	        tInvertData = Props.getValue("invertData");
	        tZoneCheck = Props.getValue("zoneCheck");
	    } else {
			var thisApp = App.getApp();
	        tDistTime = thisApp.getProperty("distTime");
	    	tAverageOver = thisApp.getProperty("averageOver");
	        tShowAsPace = thisApp.getProperty("showPace");
	        tUseOpposite = thisApp.getProperty("useOpposite");
	        tRecordData = thisApp.getProperty("recordData");
	        tInvertData = thisApp.getProperty("invertData");
	        tZoneCheck = thisApp.getProperty("zoneCheck");
	    }

       	mUseDist = (tDistTime == null) ? cUseDist : (tDistTime == 0);

		var deviceSettings = Sys.getDeviceSettings();
		mNotMetricPace = deviceSettings.paceUnits != Sys.UNIT_METRIC;
		mNotMetricDist = deviceSettings.distanceUnits != Sys.UNIT_METRIC;
       	mUseOpposite = (tUseOpposite == null) ? cUseOpposite : (tUseOpposite != 0);
       	if (mUseOpposite) {
	       	mNotMetricPace = !mNotMetricPace;
	       	mNotMetricDist = !mNotMetricDist;
		}
		
		mSlow = false;
		if (mUseDist) { // average over distance
// use default if nothing was returned from setting
			if (tAverageOver == null) {
				tAverageOver = cDistAverageOver;
			} else {
// use default if rubbish was returned from setting
				var ttAverageOver = tAverageOver.toFloat();
				if (ttAverageOver == null) {
					tAverageOver = cDistAverageOver;
				}
			}
			tfAverageOver = tAverageOver.toFloat();
		    tiAverageOver = tfAverageOver.toNumber();
			if (mNotMetricDist) {
// work out display title & convert yards/miles to metres
				if (tiAverageOver < 10) {
// Small number means big units i.e. miles not yards
					if (tfAverageOver == tiAverageOver) {
// An integer number of miles
		    	    	tUnits = tiAverageOver.toString() + "mile";
		    	    } else {
		    	    	tUnits = tfAverageOver.format("%4.2f") + "mi";
		    	    }
					tfAverageOver *= METRES_PER_MILE;

				} else {
// Big number means small units i.e. yards not miles
		    	    tUnits = tiAverageOver.toString() + "yd";
					tfAverageOver *= METRES_PER_YARD;
				}
				tiAverageOver = tfAverageOver.toNumber();
			} else {
// work out display title & maybe convert km to metres
				if (tiAverageOver < 10) {
// Small number means big units i.e. km not metres
					if (tfAverageOver == tiAverageOver) {
// An integer number of km					
		    	    	tUnits = tiAverageOver.toString() + "km";
		    	    } else {
		    	    	tUnits = tfAverageOver.format("%4.2f") + "km";
		    	    }
					tfAverageOver *= 1000.0;
				} else {
// Big number means small units i.e. metres not km
		    	    tUnits = tiAverageOver.toString() + "m";
				}
				tiAverageOver = tfAverageOver.toNumber();
			}
			if (tiAverageOver > bufLen) {
				mSlow = true;
				mMod = Math.round(((tfAverageOver / bufLen)+0.5).toNumber()) + 1;
			}
			mAverageOver = tiAverageOver;
		} else { // average over time
// use default if nothing was returned from setting
		    tiAverageOver = (tAverageOver == null) ? cTimeAverageOver : tAverageOver.toNumber();
// use default if rubbish was returned from setting
		    if (tiAverageOver == null) { tiAverageOver = cTimeAverageOver; }
		    else if (tiAverageOver == 0) { tiAverageOver = 1; }
			tUnits = tiAverageOver.toString() + "s";
			if (tiAverageOver > bufLen) {
				mSlow = true;
				mMod = Math.round(((tiAverageOver.toFloat() / bufLen)+0.5).toNumber()) + 1;
			}
			mAverageOver = tiAverageOver * 1000;
		}

		mShowAsPace = (tShowAsPace == null) ? cShowPace : (tShowAsPace == 1);
		label = tUnits + (mShowAsPace ? " Pace" : " Speed");

		mVal = mShowAsPace ? "0:00" : "0.00";
		mRate = 0.0;

// maybe set up the FITContributor
       	mRecordData = (tRecordData == null) ? cRecordData : (tRecordData != 0);
        if (mRecordData) {
	       	mInvertData = (tInvertData == null) ? cInvertData : (tInvertData != 0);
        	var units = "none";
        	if (mShowAsPace) {
        		units = "mins/" + (mNotMetricPace ? "mile" : "km");
        	} else {
        		units = (mNotMetricPace ? "mph" : "kph");
        	}
			FitPaceField = DataField.createField(
				mShowAsPace ? "Pace" : "Speed",
				PACE0_SPEED_FIELD_ID,
				FitContributor.DATA_TYPE_FLOAT,
				{:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>units}
        	);
		}
		if ( Attention has :vibrate ) {
   			mZoneCheck = (tZoneCheck == null) ? cZoneCheck : (tZoneCheck != 0);
   		} else { mZoneCheck = false; }
   		if (mZoneCheck) {
   			var ind, mins, secs, s, tm, m;
			var tUpperString;
			var tLowerString;
			
			if ( App has :Properties ) {
		        tLowerString = Props.getValue("lowerLimit");
        		tUpperString = Props.getValue("upperLimit");
	    	} else {
				var thisApp = App.getApp();
	    	    tLowerString = thisApp.getProperty("lowerLimit");
		    	tUpperString = thisApp.getProperty("upperLimit");
		    }
   			ind = tUpperString.find(":");
   			if (ind != null) {
   				mins = tUpperString.substring(0, ind);
   				secs = tUpperString.substring(ind+1, tUpperString.length()+1);
				tm = mins.toNumber();
				m = (tm == null) ? 0 : tm;
				s = secs.toNumber();
				if (s == null || s == 0) { s = (m == 0) ? 1 : 0; }
				mUpperLimitPace = ((m * 60) + s).toNumber();
				mUpperLimitSpeed = 3600.0 / mUpperLimitPace;
			} else {
				s = tUpperString.toFloat();
				if (s == null || s == 0) { s = 3600; }
				mUpperLimitPace = (3600 / s).toNumber();
				mUpperLimitSpeed = s;
			}
   			ind = tLowerString.find(":");
   			if (ind != null) {
   				mins = tLowerString.substring(0, ind);
   				secs = tLowerString.substring(ind+1, tLowerString.length()+1);
				tm = mins.toNumber();
				m = (tm == null) ? 0 : tm;
				s = secs.toNumber();
				if (s == null || s == 0) { s = (m == 0) ? 1 : 0; }
				mLowerLimitPace = ((m * 60) + s).toNumber();
				mLowerLimitSpeed = 3600.0 / mLowerLimitPace;
			} else {
				s = tLowerString.toFloat();
				if (s == null || s == 0) { s = 3600; }
				mLowerLimitPace = (3600 / s).toNumber();
				mLowerLimitSpeed = s;
			}
			if (mLowerLimitPace > mUpperLimitPace) {
				var tmp = mLowerLimitPace;
				mLowerLimitPace = mUpperLimitPace;
				mUpperLimitPace = tmp;
			} else {
				var tmp = mLowerLimitSpeed;
				mLowerLimitSpeed = mUpperLimitSpeed;
				mUpperLimitSpeed = tmp;
			}
			mVibe = [ new Attention.VibeProfile(100, 750), new Attention.VibeProfile(0, 250)];
	    }
	}
	
    //! The timer was started, so set the state to running.
    function onTimerStart()
    {
        mTimerState = TIMER_STATE_ON;
        mVal = mShowAsPace ? "0:00" : "0.00";
		mRate = 0.0;
        mDoCompute = 0;
		mJustStarted = true;
		mDoVibe = 0;
    }

    //! The timer was stopped, so set the state to stopped.
    //! and zero counters so we can restart from the beginning
    function onTimerStop()
    {
        mTimerState = TIMER_STATE_STOPPED;
        mDists[0] = 0;
        mTimes[0] = 0;
        mOldest = 0;
        mCurrent = 0;
    }

    //! The timer was paused, so set the state to paused.
    function onTimerPause()
    {
        mTimerState = TIMER_STATE_PAUSED;
    }

    //! The timer was restarted, so set the state to running again.
    function onTimerResume()
    {
        mTimerState = TIMER_STATE_ON;
		mDoVibe = 0;
    }

    //! The timer was reset, so reset all our tracking variables
    function onTimerReset()
    {
        mTimerState = TIMER_STATE_OFF;
        mVal = mShowAsPace ? "0:00" : "0.00";
		mRate = 0.0;
        mDists[0] = 0;
        mTimes[0] = 0;
        mOldest = 0;
        mCurrent = 0;
    }

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info) {
        // See Activity.Info in the documentation for available information.
		var rawDist;
		var Dist;
		var Time;
		var Rate = 0.0; // User can choose pace or speed

       	if (mNotSupported) {
       		return "Not Supported";
       	}


		// NB	info.elapsedTime is time since activity started
		//		info.timerTime is time timer has been running excluding pauses/stops
		//		shame there's no "timedDistance" :(
        if (mTimerState == TIMER_STATE_ON) {
        	if (info.timerTime == null || info.elapsedDistance == null) {
	        	if (mRecordData) {
   	    			FitPaceField.setData(mInvertData ? 0.0-mRate : mRate);
				}
        		return mVal;
        	}

        	if (mSlow) {
        		mDoCompute = (mDoCompute+1) % mMod;
        		if (mDoCompute != 1) {
		        	if (mRecordData) {
   		    			FitPaceField.setData(mInvertData ? 0.0-mRate : mRate);
					}
        			return mVal;
        		}
        	}

        	mTimes[mCurrent] = info.timerTime;
        	mDists[mCurrent] = info.elapsedDistance;

			if (mJustStarted) {
				mJustStarted = false;
    	   		mCurrent ++;
    	    	if (mRecordData) {
    	    		FitPaceField.setData(mInvertData ? 0.0-mRate : mRate);
				}
        		return mVal;
       		} else {
	        	rawDist = mDists[mCurrent] - mDists[mOldest];
    	   		Time = mTimes[mCurrent] - mTimes[mOldest];

				if (mUseDist) {
// Look for the distance nearest to the value we're averaging over
					var ind = mOldest;
					var rawDist1 = rawDist;
					var diff1 = (rawDist - mAverageOver).abs();
					var diff0 = diff1;
					while (diff1 <= diff0) {
						diff0 = diff1;
						mOldest = ind;
						rawDist = rawDist1;
						ind++;
        				if (ind >= bufLen) {
        					ind = 0;
        				}
	        			if (ind == mCurrent) {
    	    				break;
        				}
						rawDist1 = mDists[mCurrent] - mDists[ind];
						diff1 = (rawDist1 - mAverageOver).abs();
					}
		       		Time = mTimes[mCurrent] - mTimes[mOldest];
				} else {
// Look for the time nearest to the value we're averaging over
					var ind = mOldest;
					var rawTime1 = Time;
					var diff1 = (Time - mAverageOver).abs();
					var diff0 = diff1;
					while (diff1 <= diff0) {
						diff0 = diff1;
						mOldest = ind;
						Time = rawTime1;
						ind++;
        				if (ind >= bufLen) {
        					ind = 0;
        				}
	        			if (ind == mCurrent) {
    	    				break;
        				}
						rawTime1 = mTimes[mCurrent] - mTimes[ind];
						diff1 = (rawTime1 - mAverageOver).abs();
					}
	        		rawDist = mDists[mCurrent] - mDists[mOldest];
				}
			}

//  Set up mVal ready for display
// Remember distance is metres, time is milliseconds
			Dist = (mNotMetricPace) ? rawDist / KM_PER_MILE : rawDist;
            if (mShowAsPace) {
	       		Rate = (Dist != 0) ? Math.round(Time / Dist) : 0.0;
		        var Mins = (Rate / 60.0).toNumber();
		        var Secs = Math.round(Rate - (Mins * 60));

	    		if (mZoneCheck) {
			        if (Rate == 0 || Rate > mUpperLimitPace) {
						Attention.vibrate(mVibe);
					} else
			        if (Rate < mLowerLimitPace) {
			        	if (mDoVibe == 0) {
							Attention.vibrate(mVibe);
						}
			        	mDoVibe = (mDoVibe+1) % 3;
					}
				}
// for recording eg 3:24 will be displayed by Connect as 3.24
		        mRate = Mins + Secs / 100.0;
	    	    mVal = Lang.format("$1$:$2$", [Mins.format("%d"), Secs.format("%02d")]);
	       	} else { // Show as Speed
	       		// & change from milli units (metres or "milli miles") per sec to full units (kilometres or miles) per hour
	       		Rate = (Time != 0) ? ((Dist * 1000 * 3.6) / Time) : 0.0;
	       		Rate = Math.round(Rate * 100) / 100;
	    		if (mZoneCheck) {
			        if (Rate < mLowerLimitSpeed) {
						Attention.vibrate(mVibe);
					} else
			        if (Rate > mUpperLimitSpeed) {
			        	if (mDoVibe == 0) {
							Attention.vibrate(mVibe);
						}
			        	mDoVibe = (mDoVibe+1) % 3;
					}
				}
	       		mRate = Rate;
	    	    mVal = Rate.format("%4.2f");	       		
	       	}
        	if (mRecordData) {
    			FitPaceField.setData(mInvertData ? 0.0-mRate : mRate);
			}

// The rest of the code is to set up the indexes ready for data in the next call
// If the distance is greater than we're interested in, keep discarding oldest values until it's OK
// but don't let the 'oldest' index "catch up and overtake" the 'current' one
			if (mUseDist) {
	        	while (rawDist > mAverageOver && mOldest != mCurrent) {
    	    		mOldest++;
        			if (mOldest >= bufLen) {
        				mOldest = 0;
        			}
		        	rawDist = mDists[mCurrent] - mDists[mOldest];
    	    	}
			} else {
        		while (Time > mAverageOver && mOldest != mCurrent) {
        			mOldest++;
        			if (mOldest >= bufLen) {
        				mOldest = 0;
        			}
		        	Time = mTimes[mCurrent] - mTimes[mOldest];
    	    	}
			}
// Move the 'current' index on and wrap around if necessary
       		mCurrent++;
       		if (mCurrent >= bufLen) {
       			mCurrent = 0;
       		}

// Has the 'current' index "caught up" with the oldest one?
// If so, move oldest on too (which discards the oldest time and distance)
// Don't forget to wrap around
			if (mCurrent == mOldest) {
       			mOldest++;
       			if (mOldest >= bufLen) {
        			mOldest = 0;
	        	}
        	}
        }

		return mVal;
    }

}