#!/usr/bin/swift

import Foundation
func input() -> String {
    let keyboard = NSFileHandle.fileHandleWithStandardInput()
    let inputData = keyboard.availableData
    return NSString(data: inputData, encoding:NSUTF8StringEncoding) as! String
}

input()
print("Existing 1\tVal1\nHello\tVal2\n")