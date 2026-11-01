import Foundation
@main struct Checks {
 static func main() throws {
  var e = SegmentEvaluator()
  let values = [19.6,-21.3,22.2,-65.5,15,-7.9,86.3,-7.9]
  for (i,cents) in values.enumerated() {
   let t=Double(i)*0.05
   e.ingest(frequency: Twinkle.notes[0].frequency * pow(2,cents/1200), start:t,duration:0.05)
  }
  let mae=e.meanAbsoluteError(for: Phrase.all[0].notes)!
  precondition(abs(mae - 30.7125)<1e-6)
  precondition(SegmentEvaluator.passesMAE(mae))
  precondition(SegmentEvaluator.passesMAE(34.5) && !SegmentEvaluator.passesMAE(34.5001))
  precondition(!SegmentEvaluator.passesMAE(nil) && !SegmentEvaluator.passesMAE(.nan))
  precondition(SegmentEvaluator().meanAbsoluteError(for: Phrase.all[0].notes) == nil)
  let count=e.errorCount.reduce(0,+)
  e.ingest(frequency:261.6,start:0,duration:0.4)
  precondition(e.errorCount.reduce(0,+)==count)
  var progress=PracticeProgress()
  precondition(!progress.resolveMAE(40) && progress.index==0)
  precondition(progress.resolveMAE(34.5) && progress.index==1)
  var history=AttemptHistory();let id=history.begin()
  history.record(sessionID:id,phrase:Phrase.all[0],attempt:1,start:3,score:0,mae:40,useMAE:true,sampleCount:8)
  history.record(sessionID:id,phrase:Phrase.all[0],attempt:2,start:13,score:0,mae:mae,useMAE:true,sampleCount:8)
  let decoded=try JSONDecoder().decode(AttemptHistory.self,from:JSONEncoder().encode(history))
  precondition(decoded.sessions[0].finalResults.count==1 && decoded.sessions[0].finalResults[0].attempt==2)
  let legacy=AttemptRecord(id:UUID(),phraseIndex:0,attempt:1,sessionStart:0,sessionEnd:4.8,songStart:0,songEnd:4.8,score:0.6)
  precondition(!legacy.passed)
  precondition(AttemptHistory.example.sessions[0].attempts[0].passed==false)
  print("PASS: 11 MAE checks; image example = \(mae) cents, LOLOS; boundary 34.5, no-signal, absolute errors, duplicate prevention, rewind, history round-trip, legacy status")
 }
}
