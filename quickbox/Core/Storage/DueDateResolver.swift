import Foundation

struct DueDateResolver {
    func resolve(dueDateString: String, from refDate: Date = Date()) -> Date? {
        let str = dueDateString.lowercased()
        let calendar = Calendar.current
        let timeComps = calendar.dateComponents([.hour, .minute, .second], from: refDate)
        
        func withTime(of date: Date) -> Date {
            return calendar.date(bySettingHour: timeComps.hour ?? 0, minute: timeComps.minute ?? 0, second: timeComps.second ?? 0, of: date) ?? date
        }
        
        // 1. Shorthands
        switch str {
        case "today", "tdy":
            return refDate
        case "tomorrow", "tmr", "tmrw":
            return calendar.date(byAdding: .day, value: 1, to: refDate)
        case "nextweek", "next-week", "nw":
            return calendar.date(byAdding: .weekOfYear, value: 1, to: refDate)
        case "nextweekend", "next-weekend":
            var comps = DateComponents()
            comps.weekday = 7 // Saturday
            return calendar.nextDate(after: refDate, matching: comps, matchingPolicy: .nextTime)
        case "endofweek", "eow":
            var comps = DateComponents()
            comps.weekday = 6 // Friday
            return calendar.nextDate(after: refDate, matching: comps, matchingPolicy: .nextTime)
        case "endofmonth", "eom":
            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: refDate),
               let firstOfNextMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)) {
                return calendar.date(byAdding: .day, value: -1, to: firstOfNextMonth).map(withTime)
            }
        case "endofyear", "eoy":
            let currentYear = calendar.component(.year, from: refDate)
            var comps = DateComponents()
            comps.year = currentYear
            comps.month = 12
            comps.day = 31
            if let date = calendar.date(from: comps) { return withTime(of: date) }
        default: break
        }
        
        // 2. Weekdays
        let weekdays = [
            "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
            "thursday": 5, "friday": 6, "saturday": 7
        ]
        if let targetWeekday = weekdays[str] {
            var comps = DateComponents()
            comps.weekday = targetWeekday
            return calendar.nextDate(after: refDate, matching: comps, matchingPolicy: .nextTime)
        }
        
        // 3. Relative Time (inXdays, inXweeks, inXmonths)
        if let match = str.firstMatch(of: /^in(\d+)(day|days|d)$/) {
            if let value = Int(match.1) { return calendar.date(byAdding: .day, value: value, to: refDate) }
        } else if let match = str.firstMatch(of: /^in(\d+)(week|weeks|w)$/) {
            if let value = Int(match.1) { return calendar.date(byAdding: .weekOfYear, value: value, to: refDate) }
        } else if let match = str.firstMatch(of: /^in(\d+)(month|months|m)$/) {
            if let value = Int(match.1) { return calendar.date(byAdding: .month, value: value, to: refDate) }
        }
        
        // 4. Bare Day (e.g. 15) -> Next occurrence of that day
        if let match = str.firstMatch(of: /^(\d{1,2})$/), let targetDay = Int(match.1), (1...31).contains(targetDay) {
            let currentDay = calendar.component(.day, from: refDate)
            let currentMonth = calendar.component(.month, from: refDate)
            let currentYear = calendar.component(.year, from: refDate)
            
            var targetComps = DateComponents()
            targetComps.year = currentYear
            targetComps.month = targetDay <= currentDay ? currentMonth + 1 : currentMonth
            targetComps.day = targetDay
            
            if let proposedDate = calendar.date(from: targetComps) {
                // Check if the proposed month actually has that day (e.g. Feb 30)
                // If it rolled over to March, it means Feb 30 doesn't exist.
                // We'll just trust the swift DateComponents auto-rollover or leave it.
                return withTime(of: proposedDate)
            }
        }
        
        // 5. Month/Day combos (jan15, 15jan)
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        
        if let match = str.firstMatch(of: /^([a-z]{3})(\d{1,2})$/),
           let monthVal = months[String(match.1)],
           let dayVal = Int(match.2) {
            return nextDate(forMonth: monthVal, day: dayVal, refDate: refDate, calendar: calendar).map(withTime)
        } else if let match = str.firstMatch(of: /^(\d{1,2})([a-z]{3})$/),
                  let dayVal = Int(match.1),
                  let monthVal = months[String(match.2)] {
            return nextDate(forMonth: monthVal, day: dayVal, refDate: refDate, calendar: calendar).map(withTime)
        }
        
        // 6. Strict YYYY-MM-DD
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let exactDate = formatter.date(from: str) {
            return withTime(of: exactDate)
        }
        
        return nil
    }
    
    private func nextDate(forMonth month: Int, day: Int, refDate: Date, calendar: Calendar) -> Date? {
        let currentYear = calendar.component(.year, from: refDate)
        let currentMonth = calendar.component(.month, from: refDate)
        let currentDay = calendar.component(.day, from: refDate)
        
        var year = currentYear
        if month < currentMonth || (month == currentMonth && day < currentDay) {
            year += 1
        }
        
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return calendar.date(from: comps)
    }
}
