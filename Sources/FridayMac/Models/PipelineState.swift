import Foundation

enum PipelineState: String {
  case idle
  case recording
  case transcribing
  case pasted
  case error
}
