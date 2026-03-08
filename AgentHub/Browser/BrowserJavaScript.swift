import Foundation

enum ChromiumBrowserScripts {
    static func fillVisibleSearchField(query: String) -> String {
        let queryLiteral = jsStringLiteral(query)
        return """
        const query = \(queryLiteral);
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const fieldScore = (element) => {
            const descriptor = [
                element.getAttribute("aria-label"),
                element.getAttribute("placeholder"),
                element.name,
                element.id,
                element.getAttribute("role"),
                element.getAttribute("type")
            ].filter(Boolean).join(" ").toLowerCase();
            let score = 0;
            if (descriptor.includes("location") || descriptor.includes("where")) { score += 6; }
            if (descriptor.includes("restaurant")) { score += 6; }
            if (descriptor.includes("cuisine")) { score += 5; }
            if (descriptor.includes("search")) { score += 5; }
            if (descriptor.includes("combobox")) { score += 3; }
            if (descriptor.includes("text") || descriptor.length === 0) { score += 1; }
            return score;
        };
        const candidate = Array.from(document.querySelectorAll('input, textarea, [role="combobox"]'))
            .filter(isVisible)
            .sort((lhs, rhs) => fieldScore(rhs) - fieldScore(lhs))[0];
        if (!candidate) {
            throw new Error("No visible search field found.");
        }
        candidate.focus();
        candidate.value = "";
        candidate.dispatchEvent(new InputEvent("input", { bubbles: true, data: "", inputType: "deleteContentBackward" }));
        for (const character of query) {
            candidate.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: character }));
            candidate.value += character;
            candidate.dispatchEvent(new InputEvent("input", { bubbles: true, data: character, inputType: "insertText" }));
            candidate.dispatchEvent(new KeyboardEvent("keyup", { bubbles: true, key: character }));
        }
        candidate.dispatchEvent(new Event("change", { bubbles: true }));
        return {
            query,
            value: candidate.value,
            label: candidate.getAttribute("aria-label") || candidate.getAttribute("placeholder") || candidate.name || candidate.id || candidate.tagName.toLowerCase()
        };
        """
    }

    static let submitVisibleSearch = """
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const buttonLabel = (element) => [
            element.innerText,
            element.textContent,
            element.getAttribute("aria-label"),
            element.getAttribute("title"),
            element.value
        ].filter(Boolean).join(" ").toLowerCase();
        const candidates = Array.from(document.querySelectorAll('button, input[type="submit"], [role="button"]'))
            .filter(isVisible)
            .map((element) => ({ element, label: buttonLabel(element) }))
            .sort((lhs, rhs) => rhs.label.length - lhs.label.length);
        const button = candidates.find((candidate) =>
            candidate.label.includes("search")
            || candidate.label.includes("find")
            || candidate.label.includes("go")
            || candidate.label.includes("book")
        );
        if (button) {
            button.element.click();
            return { action: "click", label: button.label || "search button" };
        }
        const field = document.activeElement;
        if (field instanceof HTMLElement) {
            field.focus();
            field.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Enter", code: "Enter" }));
            field.dispatchEvent(new KeyboardEvent("keypress", { bubbles: true, key: "Enter", code: "Enter" }));
            field.dispatchEvent(new KeyboardEvent("keyup", { bubbles: true, key: "Enter", code: "Enter" }));
            if (field.form) {
                field.form.requestSubmit?.();
            }
            return { action: "enter", label: field.getAttribute("aria-label") || field.getAttribute("placeholder") || field.tagName.toLowerCase() };
        }
        throw new Error("No visible search submit control found.");
        """

    static func clickElementContainingText(_ text: String) -> String {
        let textLiteral = jsStringLiteral(text.lowercased())
        return """
        const targetText = \(textLiteral);
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim().toLowerCase();
        const candidates = Array.from(document.querySelectorAll('a[href], button, [role="button"], [role="link"]'))
            .filter(isVisible)
            .map((element) => {
                const label = normalize([
                    element.innerText,
                    element.textContent,
                    element.getAttribute("aria-label"),
                    element.getAttribute("title")
                ].filter(Boolean).join(" "));
                return { element, label };
            })
            .filter((candidate) => candidate.label.includes(targetText))
            .sort((lhs, rhs) => lhs.label.length - rhs.label.length);
        const candidate = candidates[0];
        if (!candidate) {
            throw new Error(`No visible element matched "${targetText}".`);
        }
        candidate.element.click();
        return {
            label: candidate.label,
            tag: candidate.element.tagName.toLowerCase()
        };
        """
    }

    static func clickBestRestaurantMatch(venueName: String, locationHint: String?) -> String {
        let venueLiteral = jsStringLiteral(venueName.lowercased())
        let locationLiteral = jsStringLiteral((locationHint ?? "").lowercased())
        return """
        const venueName = \(venueLiteral);
        const locationHint = \(locationLiteral);
        const normalize = (value) => (value || "")
            .toLowerCase()
            .replace(/[^a-z0-9\\s-]/g, " ")
            .replace(/\\s+/g, " ")
            .trim();
        const tokenize = (value) => normalize(value)
            .split(" ")
            .filter((token) => token.length > 1 && !["the", "and", "restaurant"].includes(token));
        const venueTokens = tokenize(venueName);
        const locationTokens = tokenize(locationHint);
        const venueSlug = venueTokens.join("-");
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const containerText = (element) => {
            const container = element.closest('article, li, [role="option"], [data-test], section, div');
            return normalize(container?.innerText || "");
        };
        const textValue = (element) => normalize([
            element.innerText,
            element.textContent,
            element.getAttribute("aria-label"),
            element.getAttribute("title")
        ].filter(Boolean).join(" "));
        const hrefValue = (element) => normalize(element.getAttribute("href") || "");
        const negativeLabel = (value) =>
            value.includes("experiences")
            || value.includes("private dining")
            || value.includes("special menus")
            || value.includes("offers");
        const candidates = Array.from(document.querySelectorAll('a[href], button, [role="button"], [role="link"]'))
            .filter(isVisible)
            .map((element) => {
                const label = textValue(element);
                const href = hrefValue(element);
                const nearby = containerText(element);
                const haystack = [label, href, nearby].join(" ");
                const matchedVenueTokens = venueTokens.filter((token) => haystack.includes(token));
                const matchedLocationTokens = locationTokens.filter((token) => haystack.includes(token));
                let score = 0;
                if (label === venueName) { score += 140; }
                if (label.includes(venueName)) { score += 90; }
                if (href.includes(venueSlug) && venueSlug.length > 2) { score += 80; }
                if (nearby.includes(venueName)) { score += 50; }
                score += matchedVenueTokens.length * 18;
                score += matchedLocationTokens.length * 12;
                if (negativeLabel(label) || negativeLabel(nearby) || negativeLabel(href)) {
                    score -= 80;
                }
                return {
                    element,
                    label,
                    href,
                    nearby,
                    score,
                    matchedVenueTokenCount: matchedVenueTokens.length,
                    matchedLocationTokenCount: matchedLocationTokens.length
                };
            })
            .filter((candidate) =>
                candidate.matchedVenueTokenCount >= Math.max(2, venueTokens.length - 1)
                || candidate.label.includes(venueName)
                || candidate.href.includes(venueSlug)
                || candidate.nearby.includes(venueName)
            )
            .sort((lhs, rhs) => rhs.score - lhs.score);
        const candidate = candidates[0];
        if (!candidate) {
            throw new Error(`No restaurant result matched "${venueName}".`);
        }
        candidate.element.click();
        return {
            venueName,
            locationHint,
            label: candidate.label,
            href: candidate.href,
            nearby: candidate.nearby,
            score: candidate.score
        };
        """
    }

    static func typeText(_ text: String, selector: String) -> String {
        let textLiteral = jsStringLiteral(text)
        let selectorLiteral = jsStringLiteral(selector)
        return """
        const selector = \(selectorLiteral);
        const value = \(textLiteral);
        const element = document.querySelector(selector);
        if (!element) {
            throw new Error(`No element matched ${selector}.`);
        }
        element.focus();
        element.value = "";
        element.dispatchEvent(new InputEvent("input", { bubbles: true, data: "", inputType: "deleteContentBackward" }));
        for (const character of value) {
            element.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: character }));
            element.value += character;
            element.dispatchEvent(new InputEvent("input", { bubbles: true, data: character, inputType: "insertText" }));
            element.dispatchEvent(new KeyboardEvent("keyup", { bubbles: true, key: character }));
        }
        element.dispatchEvent(new Event("change", { bubbles: true }));
        return { selector, value: element.value };
        """
    }

    static func clickSelector(_ selector: String) -> String {
        let selectorLiteral = jsStringLiteral(selector)
        return """
        const selector = \(selectorLiteral);
        const element = document.querySelector(selector);
        if (!element) {
            throw new Error(`No element matched ${selector}.`);
        }
        element.click();
        return { selector };
        """
    }

    static let inspectPage = """
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim();
        const interactiveElements = Array.from(document.querySelectorAll('input, button, select, textarea, a[href], [role="button"], [role="link"], [role="combobox"]'))
            .filter(isVisible)
            .slice(0, 24)
            .map((element, index) => ({
                id: `element-${index}`,
                role: element.getAttribute("role") || element.tagName.toLowerCase(),
                label: normalize([
                    element.getAttribute("aria-label"),
                    element.getAttribute("placeholder"),
                    element.name,
                    element.id,
                    element.innerText,
                    element.textContent
                ].filter(Boolean).join(" ")),
                text: normalize(element.innerText || element.textContent || "")
            }));
        return {
            title: document.title,
            url: location.href,
            formCount: document.forms.length,
            hasSearchField: interactiveElements.some((element) => /search|restaurant|location|cuisine|where/i.test(element.label)),
            interactiveElements
        };
        """

    static func retryProbe(previousURL: String, previousTitle: String) -> String {
        let previousURLLiteral = jsStringLiteral(previousURL)
        let previousTitleLiteral = jsStringLiteral(previousTitle)
        return """
        const previousURL = \(previousURLLiteral);
        const previousTitle = \(previousTitleLiteral);
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const resultCount = Array.from(document.querySelectorAll('a[href], button, [role="button"], [role="link"], li, article'))
            .filter(isVisible)
            .filter((element) => {
                const label = [
                    element.innerText,
                    element.textContent,
                    element.getAttribute("aria-label"),
                    element.getAttribute("title")
                ].filter(Boolean).join(" ").toLowerCase();
                return label.includes("reserve")
                    || label.includes("book")
                    || label.includes("restaurant")
                    || label.includes("sake house by hikari")
                    || label.includes("result");
            })
            .length;
        return {
            url: location.href,
            title: document.title,
            readyState: document.readyState,
            visibleResultCount: resultCount,
            hasDialog: !!document.querySelector('[role="dialog"], dialog, [aria-modal="true"]'),
            urlChanged: location.href !== previousURL,
            titleChanged: document.title !== previousTitle
        };
        """
    }

    static func visibleTextProbe(_ text: String) -> String {
        let textLiteral = jsStringLiteral(text.lowercased())
        return """
        const targetText = \(textLiteral);
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim().toLowerCase();
        const matches = Array.from(document.querySelectorAll('a[href], button, [role="button"], [role="link"], li, article, h1, h2, h3, span, div'))
            .filter(isVisible)
            .map((element) => normalize([
                element.innerText,
                element.textContent,
                element.getAttribute("aria-label"),
                element.getAttribute("title")
            ].filter(Boolean).join(" ")))
            .filter((label) => label.includes(targetText));
        return {
            url: location.href,
            title: document.title,
            matchCount: matches.length,
            firstMatch: matches[0] || ""
        };
        """
    }

    private static func jsStringLiteral(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return String(data: data ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
    }
}
