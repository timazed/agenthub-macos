import Foundation

enum ChromiumBrowserScripts {
    private static let textEntryHelpers = """
        const nativeValueSetter = (element) => {
            const prototypes = [];
            if (element instanceof HTMLInputElement && window.HTMLInputElement) {
                prototypes.push(window.HTMLInputElement.prototype);
            }
            if (element instanceof HTMLTextAreaElement && window.HTMLTextAreaElement) {
                prototypes.push(window.HTMLTextAreaElement.prototype);
            }
            if ("value" in element && window.HTMLElement) {
                prototypes.push(window.HTMLElement.prototype);
            }
            for (const prototype of prototypes) {
                const descriptor = Object.getOwnPropertyDescriptor(prototype, "value");
                if (descriptor?.set) {
                    return descriptor.set;
                }
            }
            return null;
        };
        const currentElementValue = (element) => {
            if (element == null) { return ""; }
            if (typeof element.value === "string") { return element.value; }
            if (element.isContentEditable) { return element.textContent || ""; }
            return "";
        };
        const setElementValue = (element, nextValue) => {
            if (element.isContentEditable) {
                element.textContent = nextValue;
                return;
            }
            const setter = nativeValueSetter(element);
            if (setter) {
                setter.call(element, nextValue);
                return;
            }
            element.value = nextValue;
        };
        const dispatchTextEntryEvents = (element, previousValue, nextValue) => {
            const inputType = nextValue.length < previousValue.length ? "deleteContentBackward" : "insertText";
            const data = nextValue === previousValue ? null : nextValue;
            try {
                element.dispatchEvent(new InputEvent("beforeinput", { bubbles: true, cancelable: true, data, inputType }));
            } catch (_) {}
            element.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
            element.dispatchEvent(new Event("change", { bubbles: true, composed: true }));
        };
        const commitTextEntry = (element, nextValue) => {
            if (!element) {
                throw new Error("No element available for text entry.");
            }
            element.focus?.();
            const previousValue = currentElementValue(element);
            if (typeof element.select === "function" && previousValue.length > 0) {
                element.select();
            }
            setElementValue(element, nextValue);
            if (typeof element.setSelectionRange === "function") {
                const caret = String(nextValue).length;
                try {
                    element.setSelectionRange(caret, caret);
                } catch (_) {}
            }
            dispatchTextEntryEvents(element, previousValue, nextValue);
            return currentElementValue(element);
        };
        """

    static func fillVisibleSearchField(query: String) -> String {
        let queryLiteral = jsStringLiteral(query)
        return """
        \(textEntryHelpers)
        const query = \(queryLiteral);
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim();
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const labelFor = (element) => normalize([
            element?.getAttribute?.("aria-label"),
            element?.getAttribute?.("placeholder"),
            element?.getAttribute?.("name"),
            element?.id,
            element?.labels ? Array.from(element.labels).map((label) => label.innerText || label.textContent).join(" ") : "",
            element?.closest?.("label")?.innerText,
            element?.innerText,
            element?.textContent
        ].filter(Boolean).join(" "));
        const isEditableSearchField = (element) => {
            if (!element || !isVisible(element)) { return false; }
            if (element instanceof HTMLTextAreaElement) { return true; }
            if (element instanceof HTMLInputElement) {
                const type = (element.type || "text").toLowerCase();
                return !["hidden", "submit", "button", "checkbox", "radio", "range", "file", "image", "reset", "color"].includes(type);
            }
            const role = (element.getAttribute?.("role") || "").toLowerCase();
            return role === "combobox" || role === "textbox" || element.isContentEditable;
        };
        const fieldScore = (element) => {
            const descriptor = [
                labelFor(element),
                element.getAttribute?.("role"),
                element.getAttribute?.("type"),
                element.getAttribute?.("autocomplete")
            ].filter(Boolean).join(" ").toLowerCase();
            let score = 0;
            if (descriptor.includes("location") || descriptor.includes("where")) { score += 6; }
            if (descriptor.includes("restaurant")) { score += 6; }
            if (descriptor.includes("cuisine")) { score += 5; }
            if (descriptor.includes("search")) { score += 5; }
            if (descriptor.includes("combobox")) { score += 3; }
            if (descriptor.includes("textbox")) { score += 3; }
            if (descriptor.includes("text") || descriptor.length === 0) { score += 1; }
            return score;
        };
        const editableSelector = 'input, textarea, [role="combobox"], [role="textbox"], [contenteditable="true"], [contenteditable=""], [contenteditable="plaintext-only"]';
        const rankEditableCandidates = () => Array.from(document.querySelectorAll(editableSelector))
            .filter(isEditableSearchField)
            .sort((lhs, rhs) => fieldScore(rhs) - fieldScore(lhs))[0];
        const clickLikelySearchTrigger = () => {
            const triggerCandidates = Array.from(document.querySelectorAll('button, [role="button"], [role="combobox"], label, [aria-label], [placeholder], div'))
                .filter(isVisible)
                .map((element) => {
                    const descriptor = labelFor(element).toLowerCase();
                    let score = 0;
                    if (descriptor.includes("location") || descriptor.includes("where")) { score += 8; }
                    if (descriptor.includes("restaurant")) { score += 8; }
                    if (descriptor.includes("cuisine")) { score += 7; }
                    if (descriptor.includes("search")) { score += 6; }
                    if (descriptor.includes("combobox")) { score += 4; }
                    if (element.querySelector?.(editableSelector)) { score += 10; }
                    return { element, score };
                })
                .filter((candidate) => candidate.score > 0)
                .sort((lhs, rhs) => rhs.score - lhs.score);
            const trigger = triggerCandidates[0]?.element;
            if (!trigger) { return null; }
            trigger.click?.();
            if (isEditableSearchField(document.activeElement)) {
                return document.activeElement;
            }
            return trigger.querySelector?.(editableSelector) || rankEditableCandidates() || null;
        };
        let candidate = rankEditableCandidates();
        if (!candidate) {
            candidate = clickLikelySearchTrigger();
        }
        if (!candidate) {
            throw new Error("No visible search field found.");
        }
        const committedValue = commitTextEntry(candidate, query);
        return {
            query,
            value: committedValue,
            label: labelFor(candidate) || candidate.tagName.toLowerCase()
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
        \(textEntryHelpers)
        const selector = \(selectorLiteral);
        const value = \(textLiteral);
        const element = document.querySelector(selector);
        if (!element) {
            throw new Error(`No element matched ${selector}.`);
        }
        const committedValue = commitTextEntry(element, value);
        return { selector, value: committedValue };
        """
    }

    static func typeVerificationCode(_ code: String) -> String {
        let codeLiteral = jsStringLiteral(code)
        return """
        \(textEntryHelpers)
        const code = \(codeLiteral);
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim();
        const normalizeLower = (value) => normalize(value).toLowerCase();
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const labelFor = (element) => normalize([
            element?.getAttribute?.("aria-label"),
            element?.getAttribute?.("placeholder"),
            element?.getAttribute?.("name"),
            element?.id,
            element?.labels ? Array.from(element.labels).map((label) => label.textContent || "").join(" ") : "",
            element?.closest?.("label")?.textContent,
            element?.textContent
        ].filter(Boolean).join(" "));
        const selectorFor = (element) => {
            if (!element || !(element instanceof Element)) { return ""; }
            if (element.id) {
                return `#${CSS.escape(element.id)}`;
            }
            if (element.getAttribute("name")) {
                return `${element.tagName.toLowerCase()}[name="${element.getAttribute("name")}"]`;
            }
            if (element.getAttribute("aria-label")) {
                return `${element.tagName.toLowerCase()}[aria-label="${element.getAttribute("aria-label")}"]`;
            }
            return element.tagName.toLowerCase();
        };
        const verificationRegex = /verification|verify|one time|one-time|passcode|security code|sms|text message|otp|pin|code/;
        const editableSelector = 'input, textarea, [role="textbox"], [contenteditable="true"], [contenteditable=""], [contenteditable="plaintext-only"]';
        const editableFields = Array.from(document.querySelectorAll(editableSelector))
            .filter(isVisible);

        const digitGroups = Array.from(document.querySelectorAll('form, [role="dialog"], dialog, section, div'))
            .filter(isVisible)
            .map((container) => {
                const fields = Array.from(container.querySelectorAll('input'))
                    .filter(isVisible)
                    .filter((field) => {
                        const maxlength = Number(field.getAttribute("maxlength") || "0");
                        const size = Number(field.getAttribute("size") || "0");
                        const descriptor = normalizeLower([
                            labelFor(field),
                            field.getAttribute("autocomplete"),
                            field.getAttribute("inputmode"),
                            field.getAttribute("type")
                        ].filter(Boolean).join(" "));
                        return maxlength == 1
                            || size == 1
                            || descriptor.includes("one-time-code")
                            || descriptor.includes("otp");
                    });
                return {
                    fields,
                    text: normalizeLower(container.textContent || "")
                };
            })
            .filter((group) => group.fields.length >= 4 && group.fields.length <= 8)
            .sort((lhs, rhs) => {
                const lhsScore = (verificationRegex.test(lhs.text) ? 10 : 0) + lhs.fields.length;
                const rhsScore = (verificationRegex.test(rhs.text) ? 10 : 0) + rhs.fields.length;
                return rhsScore - lhsScore;
            });

        const digitGroup = digitGroups[0];
        if (digitGroup) {
            const digits = code.split("");
            digitGroup.fields.slice(0, digits.length).forEach((field, index) => {
                field.focus?.();
                commitTextEntry(field, digits[index] || "");
            });
            return {
                selector: selectorFor(digitGroup.fields[0]),
                mode: "digit_group",
                digits: Math.min(digitGroup.fields.length, code.length)
            };
        }

        const bestField = editableFields
            .map((field) => {
                const descriptor = normalizeLower([
                    labelFor(field),
                    field.getAttribute("autocomplete"),
                    field.getAttribute("inputmode"),
                    field.getAttribute("type"),
                    field.closest('form, [role="dialog"], dialog, section, div')?.textContent || ""
                ].filter(Boolean).join(" "));
                let score = 0;
                if (verificationRegex.test(descriptor)) { score += 12; }
                if (descriptor.includes("one-time-code")) { score += 14; }
                if (descriptor.includes("otp")) { score += 10; }
                if (descriptor.includes("numeric") || descriptor.includes("tel") || descriptor.includes("number")) { score += 3; }
                return { field, score };
            })
            .filter((candidate) => candidate.score > 0)
            .sort((lhs, rhs) => rhs.score - lhs.score)[0]?.field;

        if (!bestField) {
            throw new Error("No visible verification field found.");
        }

        bestField.focus?.();
        const committedValue = commitTextEntry(bestField, code);
        return {
            selector: selectorFor(bestField),
            mode: "single_field",
            value: committedValue
        };
        """
    }

    static let prepareVerificationCodeAutofill = """
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim();
        const normalizeLower = (value) => normalize(value).toLowerCase();
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const labelFor = (element) => normalize([
            element?.getAttribute?.("aria-label"),
            element?.getAttribute?.("placeholder"),
            element?.getAttribute?.("name"),
            element?.id,
            element?.labels ? Array.from(element.labels).map((label) => label.textContent || "").join(" ") : "",
            element?.closest?.("label")?.textContent,
            element?.textContent
        ].filter(Boolean).join(" "));
        const selectorFor = (element) => {
            if (!element || !(element instanceof Element)) { return ""; }
            if (element.id) {
                return `#${CSS.escape(element.id)}`;
            }
            if (element.getAttribute("name")) {
                return `${element.tagName.toLowerCase()}[name="${element.getAttribute("name")}"]`;
            }
            if (element.getAttribute("aria-label")) {
                return `${element.tagName.toLowerCase()}[aria-label="${element.getAttribute("aria-label")}"]`;
            }
            return element.tagName.toLowerCase();
        };
        const verificationRegex = /verification|verify|one time|one-time|passcode|security code|sms|text message|otp|pin|code/;
        const candidates = Array.from(document.querySelectorAll('input, textarea, [role="textbox"], [contenteditable="true"], [contenteditable=""], [contenteditable="plaintext-only"]'))
            .filter(isVisible)
            .map((field) => {
                const descriptor = normalizeLower([
                    labelFor(field),
                    field.getAttribute("autocomplete"),
                    field.getAttribute("inputmode"),
                    field.getAttribute("type"),
                    field.closest('form, [role="dialog"], dialog, section, div')?.textContent || ""
                ].filter(Boolean).join(" "));
                let score = 0;
                if (verificationRegex.test(descriptor)) { score += 20; }
                if (descriptor.includes("one-time-code")) { score += 25; }
                if (descriptor.includes("otp")) { score += 12; }
                if (descriptor.includes("numeric") || descriptor.includes("tel") || descriptor.includes("number")) { score += 5; }
                return { field, score };
            })
            .filter((candidate) => candidate.score > 0)
            .sort((lhs, rhs) => rhs.score - lhs.score);
        const bestField = candidates[0]?.field;
        if (!bestField) {
            throw new Error("No visible verification field found.");
        }
        bestField.setAttribute("autocomplete", "one-time-code");
        if (!bestField.getAttribute("inputmode")) {
            bestField.setAttribute("inputmode", "numeric");
        }
        bestField.setAttribute("autocapitalize", "off");
        bestField.setAttribute("spellcheck", "false");
        bestField.click?.();
        bestField.focus?.();
        if (typeof bestField.select === "function") {
            bestField.select();
        }
        return {
            selector: selectorFor(bestField),
            label: labelFor(bestField),
            autocomplete: bestField.getAttribute("autocomplete") || "",
            inputMode: bestField.getAttribute("inputmode") || ""
        };
        """

    static func selectOption(selector: String, text: String) -> String {
        let selectorLiteral = jsStringLiteral(selector)
        let textLiteral = jsStringLiteral(text.lowercased())
        return """
        const selector = \(selectorLiteral);
        const targetText = \(textLiteral);
        const element = document.querySelector(selector);
        if (!element) {
            throw new Error(`No element matched ${selector}.`);
        }
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim().toLowerCase();
        const isVisible = (candidate) => {
            if (!candidate) { return false; }
            const style = window.getComputedStyle(candidate);
            const rect = candidate.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const optionLabel = (candidate) => normalize([
            candidate?.textContent,
            candidate?.innerText,
            candidate?.getAttribute?.("aria-label"),
            candidate?.getAttribute?.("title"),
            candidate?.getAttribute?.("value")
        ].filter(Boolean).join(" "));
        const controlDescriptor = normalize([
            element.getAttribute("aria-label"),
            element.getAttribute("placeholder"),
            element.getAttribute("name"),
            element.getAttribute("role"),
            element.textContent,
            element.closest("label, form, section, div")?.textContent
        ].filter(Boolean).join(" "));
        const isTimeTarget = /\\b\\d{1,2}(:\\d{2})?\\s?(am|pm)\\b/.test(targetText);
        const isDateTarget = /(today|tomorrow|mon|tue|wed|thu|fri|sat|sun|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|\\d{1,2})/.test(targetText);
        const controlIntent = /time|seating/.test(controlDescriptor) ? "time"
            : (/date|calendar|check-in|checkout|arrival|departure|day/.test(controlDescriptor) ? "date"
            : (/guest|party|people|traveler|traveller|passenger|room/.test(controlDescriptor) ? "guest" : ""));
        const collectRoots = () => {
            const roots = [];
            const pushRoot = (candidate) => {
                if (!candidate || roots.includes(candidate)) { return; }
                roots.push(candidate);
            };
            const controlledIDs = [
                element.getAttribute("aria-controls"),
                element.getAttribute("aria-owns")
            ]
                .filter(Boolean)
                .flatMap((value) => value.split(/\\s+/))
                .filter(Boolean);
            for (const id of controlledIDs) {
                pushRoot(document.getElementById(id));
            }
            const popupContainers = Array.from(document.querySelectorAll('[role="listbox"], [role="menu"], [role="dialog"], dialog, [aria-modal="true"], [data-testid*="popover" i], [data-testid*="dropdown" i], [data-testid*="picker" i], [data-test*="popover" i], [data-test*="dropdown" i], [data-test*="picker" i], [class*="popover" i], [class*="dropdown" i], [class*="picker" i], [class*="menu" i]'))
                .filter(isVisible);
            popupContainers.forEach(pushRoot);
            pushRoot(element.closest('[role="dialog"], dialog, form, section, article, div'));
            pushRoot(element.parentElement);
            pushRoot(document.body);
            return roots;
        };
        const clickLike = (candidate) => {
            candidate.scrollIntoView({ block: "center", inline: "center" });
            candidate.click?.();
        };
        if (element instanceof HTMLSelectElement) {
            const option = Array.from(element.options).find((candidate) => {
                const label = normalize(candidate.textContent || candidate.label || candidate.value);
                return label === targetText || label.includes(targetText) || normalize(candidate.value) === targetText;
            });
            if (!option) {
                throw new Error(`No option matched ${targetText}.`);
            }
            element.value = option.value;
            element.dispatchEvent(new Event("input", { bubbles: true }));
            element.dispatchEvent(new Event("change", { bubbles: true }));
            return { selector, value: option.value, label: option.textContent || option.label || option.value };
        }
        clickLike(element);
        const roots = collectRoots();
        const candidates = Array.from(new Set(
            roots.flatMap((root) => Array.from(root.querySelectorAll('option, [role="option"], button, [role="button"], [role="menuitem"], [role="link"], a[href], li, td, [aria-selected="true"], [aria-selected="false"]')))
        ))
            .filter((candidate) => candidate !== element && isVisible(candidate))
            .map((candidate) => {
                const label = optionLabel(candidate);
                const nearby = normalize(candidate.closest('[role="option"], [role="menuitem"], li, td, [role="dialog"], dialog, [role="listbox"], [role="menu"], section, article, div')?.textContent || "");
                let score = -200;
                if (!label) {
                    return { candidate, label, score };
                }
                if (label === targetText) { score += 260; }
                else if (label.includes(targetText) || targetText.includes(label)) { score += 200; }
                if (nearby.includes(targetText)) { score += 60; }
                if (isTimeTarget && /\\b\\d{1,2}(:\\d{2})?\\s?(am|pm)\\b/.test(label)) { score += 70; }
                if (isDateTarget && /(today|tomorrow|mon|tue|wed|thu|fri|sat|sun|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|\\d{1,2})/.test(label)) { score += 55; }
                if (controlIntent === "time" && /time|seating/.test(`${label} ${nearby}`)) { score += 35; }
                if (controlIntent === "date" && /date|calendar|arrival|departure|day/.test(`${label} ${nearby}`)) { score += 35; }
                if (controlIntent === "guest" && /guest|party|people|traveler|traveller|passenger|room/.test(`${label} ${nearby}`)) { score += 35; }
                if (candidate.closest('[role="listbox"], [role="menu"], [role="dialog"], dialog, [aria-modal="true"]')) { score += 40; }
                if (candidate.closest('[data-testid*="popover" i], [data-testid*="dropdown" i], [data-testid*="picker" i], [data-test*="popover" i], [data-test*="dropdown" i], [data-test*="picker" i], [class*="popover" i], [class*="dropdown" i], [class*="picker" i], [class*="menu" i]')) { score += 25; }
                if (label.length > 80) { score -= 50; }
                if (/save|favorite|share|help|map|directions/.test(`${label} ${nearby}`)) { score -= 120; }
                return { candidate, label, score };
            })
            .filter((entry) => entry.score > 0)
            .sort((lhs, rhs) => rhs.score - lhs.score);
        const match = candidates[0];
        if (!match) {
            throw new Error(`Element matched by ${selector} is not a native select element and no custom option matched ${targetText}.`);
        }
        clickLike(match.candidate);
        return { selector, value: targetText, label: match.label, custom: true };
        """
    }

    static func chooseAutocompleteOption(selector: String?, text: String) -> String {
        let selectorLiteral = selector.map(jsStringLiteral) ?? "null"
        let textLiteral = jsStringLiteral(text)
        return """
        const selector = \(selectorLiteral);
        const targetText = \(textLiteral);
        const normalizedTarget = (targetText || "").replace(/\\s+/g, " ").trim().toLowerCase();
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim();
        const normalizeLower = (value) => normalize(value).toLowerCase();
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const labelFor = (element) => normalize([
            element?.getAttribute?.("aria-label"),
            element?.getAttribute?.("placeholder"),
            element?.getAttribute?.("name"),
            element?.id,
            element?.labels ? Array.from(element.labels).map((label) => label.innerText || label.textContent).join(" ") : "",
            element?.closest?.("label")?.innerText,
            element?.innerText,
            element?.textContent
        ].filter(Boolean).join(" "));
        const matchScore = (value) => {
            const normalizedValue = normalizeLower(value);
            if (!normalizedValue) { return 0; }
            if (normalizedValue === normalizedTarget) { return 120; }
            if (normalizedValue.includes(normalizedTarget)) { return 90; }
            if (normalizedTarget.includes(normalizedValue)) { return 40; }
            return 0;
        };
        const resolveInput = () => {
            if (selector) {
                const matched = document.querySelector(selector);
                if (!matched) {
                    throw new Error(`No element matched ${selector}.`);
                }
                return matched;
            }
            const active = document.activeElement;
            if (active && active.matches?.('input, textarea, [role="combobox"]') && isVisible(active)) {
                return active;
            }
            const scoreInput = (element) => {
                const descriptor = normalizeLower([
                    labelFor(element),
                    element.getAttribute("autocomplete"),
                    element.getAttribute("role"),
                    element.getAttribute("type")
                ].join(" "));
                let score = 0;
                if (/search|destination|location|city|airport|where|from|to/.test(descriptor)) { score += 60; }
                if (/guest|traveler|traveller|passenger|party|people|room/.test(descriptor)) { score += 45; }
                if (element.getAttribute("aria-controls") || element.getAttribute("list")) { score += 40; }
                if (descriptor.includes("combobox")) { score += 30; }
                return score;
            };
            return Array.from(document.querySelectorAll('input, textarea, [role="combobox"]'))
                .filter(isVisible)
                .sort((lhs, rhs) => scoreInput(rhs) - scoreInput(lhs))[0];
        };
        const input = resolveInput();
        if (!input) {
            throw new Error("No autocomplete input is available.");
        }
        input.focus?.();
        const containers = [];
        const controlledId = input.getAttribute?.("aria-controls") || input.getAttribute?.("list");
        if (controlledId) {
            const controlled = document.getElementById(controlledId);
            if (controlled) {
                containers.push(controlled);
            }
        }
        if (input.list) {
            containers.push(input.list);
        }
        const nearbyList = input.closest?.('[role="combobox"], form, section, div')?.querySelector?.('[role="listbox"], datalist, ul, ol');
        if (nearbyList) {
            containers.push(nearbyList);
        }
        const globalList = document.querySelector('[role="listbox"], datalist');
        if (globalList) {
            containers.push(globalList);
        }
        const seen = new Set();
        const optionCandidates = [];
        for (const container of containers) {
            if (!container || seen.has(container)) { continue; }
            seen.add(container);
            if (container instanceof HTMLDataListElement) {
                for (const option of Array.from(container.options)) {
                    optionCandidates.push({
                        element: option,
                        label: normalize(option.label || option.value || option.textContent || ""),
                        mode: "datalist"
                    });
                }
                continue;
            }
            const options = Array.from(container.querySelectorAll('[role="option"], option, li, button, a[href], div'))
                .filter(isVisible)
                .map((option) => ({
                    element: option,
                    label: normalize(option.textContent || option.getAttribute("aria-label") || option.getAttribute("data-value") || ""),
                    mode: "click"
                }))
                .filter((candidate) => candidate.label);
            optionCandidates.push(...options);
        }
        if (!optionCandidates.length) {
            const fallbackOptions = Array.from(document.querySelectorAll('[role="option"], li, button, a[href]'))
                .filter(isVisible)
                .map((option) => ({
                    element: option,
                    label: normalize(option.textContent || option.getAttribute("aria-label") || ""),
                    mode: "click"
                }))
                .filter((candidate) => candidate.label);
            optionCandidates.push(...fallbackOptions);
        }
        const bestOption = optionCandidates
            .map((candidate) => ({ ...candidate, score: matchScore(candidate.label) }))
            .filter((candidate) => candidate.score > 0)
            .sort((lhs, rhs) => rhs.score - lhs.score)[0];
        if (!bestOption) {
            throw new Error(`No autocomplete option matched ${targetText}.`);
        }
        if (bestOption.mode === "datalist") {
            input.value = bestOption.label;
            input.dispatchEvent(new InputEvent("input", { bubbles: true, data: bestOption.label, inputType: "insertReplacementText" }));
            input.dispatchEvent(new Event("change", { bubbles: true }));
            return {
                selector: selector || "",
                inputLabel: labelFor(input),
                optionLabel: bestOption.label,
                mode: "datalist"
            };
        }
        bestOption.element.scrollIntoView?.({ block: "center", inline: "nearest" });
        bestOption.element.click?.();
        return {
            selector: selector || "",
            inputLabel: labelFor(input),
            optionLabel: bestOption.label,
            mode: "click"
        };
        """
    }

    static func chooseGroupedOption(selector: String?, groupLabel: String?, text: String) -> String {
        let selectorLiteral = selector.map(jsStringLiteral) ?? "null"
        let groupLabelLiteral = groupLabel.map(jsStringLiteral) ?? "null"
        let textLiteral = jsStringLiteral(text)
        return """
        const selector = \(selectorLiteral);
        const targetGroupLabel = (\(groupLabelLiteral) || "").replace(/\\s+/g, " ").trim().toLowerCase();
        const targetText = \(textLiteral);
        const normalizedTarget = (targetText || "").replace(/\\s+/g, " ").trim().toLowerCase();
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim();
        const normalizeLower = (value) => normalize(value).toLowerCase();
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const labelFor = (element) => normalize([
            element?.getAttribute?.("aria-label"),
            element?.getAttribute?.("name"),
            element?.id,
            element?.querySelector?.("legend, h1, h2, h3, h4, [role='heading']")?.textContent,
            element?.closest?.("label")?.innerText,
            element?.innerText,
            element?.textContent
        ].filter(Boolean).join(" "));
        const scoreMatch = (target, value) => {
            if (!target) { return 0; }
            const normalizedValue = normalizeLower(value);
            if (!normalizedValue) { return 0; }
            if (normalizedValue === target) { return 120; }
            if (normalizedValue.includes(target)) { return 90; }
            if (target.includes(normalizedValue)) { return 30; }
            return 0;
        };
        const optionDescriptor = (option) => normalize([
            labelFor(option),
            option?.value,
            option?.getAttribute?.("data-value"),
            option?.closest?.("label")?.innerText,
            option?.parentElement?.innerText
        ].filter(Boolean).join(" "));
        const optionSelected = (option) =>
            option?.getAttribute?.("aria-selected") === "true"
            || option?.getAttribute?.("aria-checked") === "true"
            || option?.checked === true
            || option?.classList?.contains?.("active") === true;
        const triggerOption = (option) => {
            if (option instanceof HTMLLabelElement && option.control) {
                option.click();
                return option.control;
            }
            if (option instanceof HTMLInputElement && (option.type === "radio" || option.type === "checkbox")) {
                option.focus();
                option.click();
                option.dispatchEvent(new Event("input", { bubbles: true }));
                option.dispatchEvent(new Event("change", { bubbles: true }));
                return option;
            }
            option.click?.();
            return option;
        };
        const resolveGroups = () => {
            if (selector) {
                const matched = document.querySelector(selector);
                if (!matched) {
                    throw new Error(`No element matched ${selector}.`);
                }
                const group = matched.closest?.('[role="tablist"], [role="radiogroup"], [role="listbox"], fieldset, nav')
                    || (matched.matches?.('[role="tablist"], [role="radiogroup"], [role="listbox"], fieldset, nav') ? matched : null);
                return group ? [group] : [matched];
            }
            return Array.from(document.querySelectorAll('[role="tablist"], [role="radiogroup"], [role="listbox"], fieldset, nav'))
                .filter(isVisible);
        };
        const groups = resolveGroups();
        const rankedGroups = groups
            .map((group) => {
                const options = Array.from(group.querySelectorAll('button, [role="tab"], [role="radio"], [role="option"], a[href], input[type="radio"], input[type="checkbox"], label'))
                    .filter(isVisible)
                    .map((option) => ({
                        element: option,
                        label: optionDescriptor(option),
                        score: scoreMatch(normalizedTarget, optionDescriptor(option)),
                        isSelected: optionSelected(option)
                    }))
                    .filter((option) => option.label);
                const bestOption = options
                    .filter((option) => option.score > 0)
                    .sort((lhs, rhs) => rhs.score - lhs.score)[0];
                return {
                    element: group,
                    label: labelFor(group),
                    options,
                    groupScore: scoreMatch(targetGroupLabel, labelFor(group)),
                    bestOption
                };
            })
            .filter((group) => group.bestOption)
            .sort((lhs, rhs) => (rhs.groupScore + rhs.bestOption.score) - (lhs.groupScore + lhs.bestOption.score));
        const bestGroup = rankedGroups[0];
        if (!bestGroup) {
            throw new Error(`No grouped control option matched ${targetText}.`);
        }
        if (bestGroup.bestOption.isSelected) {
            return {
                groupLabel: bestGroup.label,
                optionLabel: bestGroup.bestOption.label,
                alreadySelected: true
            };
        }
        const activated = triggerOption(bestGroup.bestOption.element);
        return {
            groupLabel: bestGroup.label,
            optionLabel: bestGroup.bestOption.label,
            selector: activated ? (activated.id ? `#${activated.id}` : activated.tagName.toLowerCase()) : "",
            alreadySelected: false
        };
        """
    }

    static func pickDate(selector: String?, text: String) -> String {
        let selectorLiteral = selector.map(jsStringLiteral) ?? "null"
        let textLiteral = jsStringLiteral(text)
        return """
        const selector = \(selectorLiteral);
        const targetText = \(textLiteral);
        const normalizedTarget = (targetText || "").replace(/\\s+/g, " ").trim().toLowerCase();
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim();
        const normalizeLower = (value) => normalize(value).toLowerCase();
        const datePartsFor = (date) => {
            if (!(date instanceof Date) || Number.isNaN(date.getTime())) { return null; }
            return {
                year: date.getFullYear(),
                month: date.getMonth() + 1,
                day: date.getDate()
            };
        };
        const parseDateValue = (value) => {
            const normalizedValue = normalize(value);
            if (!normalizedValue) { return null; }
            if (/^\\d{4}-\\d{2}-\\d{2}$/.test(normalizedValue)) {
                return datePartsFor(new Date(`${normalizedValue}T12:00:00`));
            }
            const directParts = datePartsFor(new Date(normalizedValue));
            if (directParts) {
                return directParts;
            }
            const monthMatch = normalizedValue.match(/(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)/i);
            const dayMatch = normalizedValue.match(/\\b(\\d{1,2})\\b/);
            if (!monthMatch || !dayMatch) { return null; }
            const monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
            const month = monthNames.findIndex((prefix) => monthMatch[1].toLowerCase().startsWith(prefix)) + 1;
            if (month <= 0) { return null; }
            const yearMatch = normalizedValue.match(/\\b(20\\d{2})\\b/);
            const year = yearMatch ? Number(yearMatch[1]) : new Date().getFullYear();
            return {
                year,
                month,
                day: Number(dayMatch[1])
            };
        };
        const sameCalendarDay = (lhs, rhs) =>
            !!lhs
                && !!rhs
                && lhs.year === rhs.year
                && lhs.month === rhs.month
                && lhs.day === rhs.day;
        const targetDate = parseDateValue(targetText);
        const targetDayNumber = targetDate?.day ?? (/^\\d{1,2}$/.test(normalizedTarget) ? Number(normalizedTarget) : null);
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const labelFor = (element) => normalize([
            element?.getAttribute?.("aria-label"),
            element?.getAttribute?.("placeholder"),
            element?.getAttribute?.("name"),
            element?.id,
            element?.closest?.("label")?.innerText,
            element?.innerText,
            element?.textContent
        ].filter(Boolean).join(" "));
        const dateScore = (value) => {
            const normalizedValue = normalizeLower(value);
            if (!normalizedValue) { return 0; }
            const parsedValue = parseDateValue(value);
            if (targetDate && sameCalendarDay(targetDate, parsedValue)) { return 180; }
            if (normalizedValue === normalizedTarget) { return 140; }
            if (normalizedValue.includes(normalizedTarget)) { return 110; }
            if (targetDayNumber != null && /^\\d{1,2}$/.test(normalizedValue) && Number(normalizedValue) == targetDayNumber) {
                return 95;
            }
            return 0;
        };
        const resolveTrigger = () => {
            if (selector) {
                const matched = document.querySelector(selector);
                if (!matched) {
                    throw new Error(`No element matched ${selector}.`);
                }
                return matched;
            }
            const active = document.activeElement;
            if (active && isVisible(active) && /date|calendar|check-in|check out|checkout|arrival|departure/i.test(labelFor(active))) {
                return active;
            }
            const candidates = Array.from(document.querySelectorAll('input, button, [role="button"], [role="combobox"]'))
                .filter(isVisible)
                .sort((lhs, rhs) => dateScore(labelFor(rhs)) - dateScore(labelFor(lhs)));
            return candidates[0];
        };
        const trigger = resolveTrigger();
        if (!trigger) {
            throw new Error("No date control is available.");
        }
        if (trigger instanceof HTMLInputElement && trigger.type === "date" && /^\\d{4}-\\d{2}-\\d{2}$/.test(targetText)) {
            trigger.focus();
            trigger.value = targetText;
            trigger.dispatchEvent(new InputEvent("input", { bubbles: true, data: targetText, inputType: "insertReplacementText" }));
            trigger.dispatchEvent(new Event("change", { bubbles: true }));
            return {
                mode: "native_input",
                label: labelFor(trigger),
                value: trigger.value
            };
        }
        trigger.click?.();
        const calendarContainers = Array.from(document.querySelectorAll('[role="dialog"], dialog, [aria-modal="true"], [role="grid"], table, [aria-label*="calendar" i], [data-testid*="calendar" i], [data-test*="calendar" i]'))
            .filter(isVisible);
        const dayCandidates = Array.from((calendarContainers.length ? calendarContainers : [document]).flatMap((container) =>
            Array.from(container.querySelectorAll('button, [role="gridcell"], td, [role="option"]'))
        ))
            .filter(isVisible)
            .map((element) => {
                const label = normalize([
                    element.getAttribute("aria-label"),
                    element.getAttribute("data-date"),
                    element.getAttribute("datetime"),
                    element.textContent
                ].filter(Boolean).join(" "));
                return {
                    element,
                    label,
                    score: dateScore(label)
                };
            })
            .filter((candidate) =>
                candidate.score > 0
                && !/next|previous|prev|month|calendar/i.test(candidate.label)
                && candidate.element.getAttribute("aria-disabled") !== "true"
                && candidate.element.getAttribute("disabled") == null
            )
            .sort((lhs, rhs) => rhs.score - lhs.score);
        const bestDay = dayCandidates[0];
        if (bestDay) {
            const clickTarget = bestDay.element.querySelector?.('button, [role="button"]') || bestDay.element;
            clickTarget.click?.();
            return {
                mode: "calendar_click",
                label: labelFor(trigger),
                value: bestDay.label
            };
        }
        if (trigger instanceof HTMLInputElement) {
            trigger.focus();
            trigger.value = targetText;
            trigger.dispatchEvent(new InputEvent("input", { bubbles: true, data: targetText, inputType: "insertText" }));
            trigger.dispatchEvent(new Event("change", { bubbles: true }));
            return {
                mode: "text_input",
                label: labelFor(trigger),
                value: trigger.value
            };
        }
        throw new Error(`No visible date matched ${targetText}.`);
        """
    }

    static func submitForm(selector: String?, label: String?) -> String {
        let selectorLiteral = selector.map(jsStringLiteral) ?? "null"
        let labelLiteral = label.map(jsStringLiteral) ?? "null"
        return """
        const selector = \(selectorLiteral);
        const targetLabel = (\(labelLiteral) || "").replace(/\\s+/g, " ").trim().toLowerCase();
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim();
        const normalizeLower = (value) => normalize(value).toLowerCase();
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const labelFor = (element) => normalize([
            element?.getAttribute?.("aria-label"),
            element?.getAttribute?.("name"),
            element?.id,
            element?.querySelector?.("legend, h1, h2, h3, h4, [role='heading']")?.textContent,
            element?.innerText,
            element?.textContent,
            element?.value
        ].filter(Boolean).join(" "));
        const scoreMatch = (value) => {
            if (!targetLabel) { return 0; }
            const normalizedValue = normalizeLower(value);
            if (!normalizedValue) { return 0; }
            if (normalizedValue === targetLabel) { return 120; }
            if (normalizedValue.includes(targetLabel)) { return 90; }
            if (targetLabel.includes(normalizedValue)) { return 30; }
            return 0;
        };
        const actionScore = (value) => {
            const normalizedValue = normalizeLower(value);
            let score = 0;
            if (/search|find|show results/.test(normalizedValue)) { score += 80; }
            if (/continue|next|apply|submit|done/.test(normalizedValue)) { score += 70; }
            if (/reserve|book|checkout|confirm|purchase|pay/.test(normalizedValue)) { score += 120; }
            score += scoreMatch(value);
            return score;
        };
        const submitCandidatesFor = (form) => Array.from(form.querySelectorAll('button, input[type="submit"], [role="button"]'))
            .filter(isVisible)
            .map((element) => ({
                element,
                label: labelFor(element),
                score: actionScore(labelFor(element))
            }))
            .sort((lhs, rhs) => rhs.score - lhs.score);
        let form = null;
        if (selector) {
            const matched = document.querySelector(selector);
            if (!matched) {
                throw new Error(`No element matched ${selector}.`);
            }
            form = matched instanceof HTMLFormElement ? matched : matched.closest?.("form");
        }
        if (!form) {
            const forms = Array.from(document.querySelectorAll('form'))
                .filter(isVisible)
                .map((candidate) => {
                    const submitCandidates = submitCandidatesFor(candidate);
                    const fieldLabels = Array.from(candidate.querySelectorAll('input, select, textarea, [role="combobox"]'))
                        .filter(isVisible)
                        .map((field) => labelFor(field))
                        .join(" ");
                    return {
                        element: candidate,
                        label: labelFor(candidate),
                        score: scoreMatch(labelFor(candidate)) + scoreMatch(fieldLabels) + (submitCandidates[0]?.score || 0)
                    };
                })
                .sort((lhs, rhs) => rhs.score - lhs.score);
            form = forms[0]?.element || null;
        }
        if (form) {
            const submitCandidates = submitCandidatesFor(form);
            const submitCandidate = submitCandidates[0];
            if (submitCandidate) {
                submitCandidate.element.click?.();
                return {
                    mode: "click_submit",
                    formLabel: labelFor(form),
                    submitLabel: submitCandidate.label
                };
            }
            form.requestSubmit?.();
            return {
                mode: "request_submit",
                formLabel: labelFor(form),
                submitLabel: ""
            };
        }
        const fallback = Array.from(document.querySelectorAll('button, input[type="submit"], [role="button"]'))
            .filter(isVisible)
            .map((element) => ({
                element,
                label: labelFor(element),
                score: actionScore(labelFor(element))
            }))
            .filter((candidate) => candidate.score > 0)
            .sort((lhs, rhs) => rhs.score - lhs.score)[0];
        if (!fallback) {
            throw new Error("No visible form or submit control matched.");
        }
        fallback.element.click?.();
        return {
            mode: "fallback_click",
            formLabel: "",
            submitLabel: fallback.label
        };
        """
    }

    static func pressKey(_ key: String) -> String {
        let keyLiteral = jsStringLiteral(key)
        return """
        const key = \(keyLiteral);
        const element = document.activeElement;
        if (!(element instanceof HTMLElement)) {
            throw new Error("No active element available for key press.");
        }
        element.focus();
        element.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key, code: key }));
        element.dispatchEvent(new KeyboardEvent("keypress", { bubbles: true, key, code: key }));
        element.dispatchEvent(new KeyboardEvent("keyup", { bubbles: true, key, code: key }));
        return {
            key,
            tag: element.tagName.toLowerCase(),
            label: element.getAttribute("aria-label") || element.getAttribute("placeholder") || element.id || element.className || ""
        };
        """
    }

    static func scrollBy(deltaY: Double) -> String {
        """
        const deltaY = \(deltaY);
        window.scrollBy({ top: deltaY, behavior: "instant" });
        return {
            deltaY,
            scrollY: window.scrollY,
            innerHeight: window.innerHeight,
            scrollHeight: document.documentElement ? document.documentElement.scrollHeight : 0
        };
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

    static func probeSelector(_ selector: String) -> String {
        let selectorLiteral = jsStringLiteral(selector)
        return """
        const selector = \(selectorLiteral);
        const element = document.querySelector(selector);
        const text = element ? ((element.innerText || element.textContent || "").replace(/\\s+/g, " ").trim()) : "";
        return {
            url: window.location.href,
            title: document.title,
            selector,
            found: !!element,
            text
        };
        """
    }

    static func navigationProbe(previousURL: String, previousTitle: String, expectedURLFragment: String?) -> String {
        let previousURLLiteral = jsStringLiteral(previousURL)
        let previousTitleLiteral = jsStringLiteral(previousTitle)
        let expectedURLFragmentLiteral = jsStringLiteral((expectedURLFragment ?? "").lowercased())
        return """
        const previousURL = \(previousURLLiteral);
        const previousTitle = \(previousTitleLiteral);
        const expectedURLFragment = \(expectedURLFragmentLiteral);
        const currentURL = window.location.href;
        const currentTitle = document.title || "";
        const changed = currentURL !== previousURL || currentTitle !== previousTitle;
        const matchesExpected = !expectedURLFragment || currentURL.toLowerCase().includes(expectedURLFragment);
        return {
            url: currentURL,
            title: currentTitle,
            selector: "",
            found: changed && matchesExpected,
            text: document.body ? (document.body.innerText || "").replace(/\\s+/g, " ").trim().slice(0, 400) : ""
        };
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
        const normalizeLower = (value) => normalize(value).toLowerCase();
        const escapePart = (value) => {
            const stringValue = String(value || "");
            if (window.CSS && typeof window.CSS.escape === "function") {
                return window.CSS.escape(stringValue);
            }
            return stringValue.replace(/[^a-zA-Z0-9_-]/g, "\\\\$&");
        };
        const selectorFor = (element) => {
            if (!element || !(element instanceof Element)) { return ""; }
            if (element.id) {
                return `#${escapePart(element.id)}`;
            }
            const testId = element.getAttribute("data-testid") || element.getAttribute("data-test");
            if (testId) {
                return `[data-testid="${testId}"], [data-test="${testId}"]`;
            }
            if (element.getAttribute("name")) {
                return `${element.tagName.toLowerCase()}[name="${element.getAttribute("name")}"]`;
            }
            if (element.getAttribute("aria-label")) {
                return `${element.tagName.toLowerCase()}[aria-label="${element.getAttribute("aria-label")}"]`;
            }
            const parts = [];
            let current = element;
            while (current && current.nodeType === Node.ELEMENT_NODE && parts.length < 4) {
                let part = current.tagName.toLowerCase();
                if (current.id) {
                    part += `#${escapePart(current.id)}`;
                    parts.unshift(part);
                    break;
                }
                const siblings = current.parentElement
                    ? Array.from(current.parentElement.children).filter((candidate) => candidate.tagName === current.tagName)
                    : [];
                if (siblings.length > 1) {
                    const index = siblings.indexOf(current) + 1;
                    part += `:nth-of-type(${index})`;
                }
                parts.unshift(part);
                current = current.parentElement;
            }
            return parts.join(" > ");
        };
        const labelFor = (element) => {
            if (!element) { return ""; }
            const tagName = element.tagName?.toLowerCase?.() || "";
            const selectedOptionLabel = element instanceof HTMLSelectElement
                ? normalize(element.selectedOptions?.[0]?.textContent || element.value || "")
                : "";
            const explicitLabel = normalize([
                element.getAttribute?.("aria-label"),
                element.getAttribute?.("placeholder"),
                element.getAttribute?.("name"),
                element.id,
                element.labels ? Array.from(element.labels).map((label) => label.textContent || "").join(" ") : "",
                element.closest?.("label")?.textContent
            ].filter(Boolean).join(" "));
            if (explicitLabel) {
                if (tagName === "select" && selectedOptionLabel && selectedOptionLabel.toLowerCase() !== explicitLabel.toLowerCase()) {
                    return normalize([explicitLabel, selectedOptionLabel].join(" "));
                }
                return explicitLabel;
            }
            if (tagName === "select" && selectedOptionLabel) { return selectedOptionLabel; }
            if (/input|textarea/.test(tagName)) {
                return normalize([
                    element.getAttribute?.("aria-label"),
                    element.getAttribute?.("placeholder"),
                    element.labels ? Array.from(element.labels).map((label) => label.textContent || "").join(" ") : "",
                    element.closest?.("label")?.textContent
                ].filter(Boolean).join(" "));
            }
            return normalize([
                element.innerText,
                element.textContent
            ].filter(Boolean).join(" "));
        };
        const isAuthChoiceAction = (label) => /use email instead|continue with email|continue with phone|use phone instead|sign in|log in|login|verify account|verify your account/.test(normalizeLower(label));
        const isSkipNavigationAction = (label) => /skip to main content|skip navigation|skip to content/.test(normalizeLower(label));
        const isUtilityAction = (label) => /save|favorite|favourite|share|help|map|directions|bookmark/.test(normalizeLower(label));
        const isFormLikeContainer = (element) => !!element?.closest?.('form, [role="dialog"], dialog, [aria-modal="true"], [data-testid*="form" i], [data-test*="form" i], [class*="form" i]');
        const isResultLikeContainer = (element) => {
            if (!element || isFormLikeContainer(element)) { return false; }
            const directItems = Array.from(element.querySelectorAll(':scope > li, :scope > article, :scope > div, :scope > [role="listitem"], :scope > a[href]'))
                .filter(isVisible);
            if (directItems.length < 3) { return false; }
            const formControlCount = element.querySelectorAll('input, select, textarea, [role="textbox"], [role="combobox"]').length;
            const navigationCount = element.querySelectorAll('a[href], button, [role="button"], [role="link"]').length;
            return navigationCount >= 2 && formControlCount <= 1;
        };
        const hasLargeSelectLabel = (label) => normalize(label).length > 120;
        const inferPurpose = (element, label) => {
            const descriptor = normalizeLower([
                label,
                element?.getAttribute?.("type"),
                element?.getAttribute?.("role"),
                element?.getAttribute?.("autocomplete"),
                element?.getAttribute?.("inputmode")
            ].filter(Boolean).join(" "));
            if (/one-time-code|verification|passcode|otp|security code|auth code/.test(descriptor)) { return "verification_code"; }
            if (/email|e-mail/.test(descriptor)) { return "email"; }
            if (/phone|mobile|telephone|contact number|tel/.test(descriptor)) { return "phone_number"; }
            if (/first name|given name/.test(descriptor)) { return "first_name"; }
            if (/last name|family name|surname/.test(descriptor)) { return "last_name"; }
            if (/\\bfull name\\b|\\byour name\\b|\\bguest name\\b|\\btraveler name\\b|\\bpassenger name\\b/.test(descriptor)) { return "full_name"; }
            if (/address line 1|street address|billing address|delivery address|shipping address/.test(descriptor)) { return "address_line1"; }
            if (/address line 2|apt|suite|unit|apartment/.test(descriptor)) { return "address_line2"; }
            if (/\\bcity\\b|\\btown\\b/.test(descriptor)) { return "city"; }
            if (/\\bstate\\b|\\bprovince\\b|\\bregion\\b/.test(descriptor)) { return "state"; }
            if (/zip|postal/.test(descriptor)) { return "postal_code"; }
            if (/\\bcountry\\b/.test(descriptor)) { return "country"; }
            if (/card number|credit card|debit card|payment card/.test(descriptor)) { return "payment_card_number"; }
            if (/cvv|cvc|security code/.test(descriptor)) { return "payment_security_code"; }
            if (/exp|expiry|expiration/.test(descriptor)) { return "payment_expiry"; }
            if (/terms|conditions|consent|agree|newsletter|marketing|updates|reminders|text updates|text reminders/.test(descriptor)) { return "consent"; }
            if (/destination|where|location|from|to|city|airport/.test(descriptor)) { return "location"; }
            if (/search|find|look up/.test(descriptor)) { return "search"; }
            if (/date|calendar|check-in|check out|checkout|arrival|departure/.test(descriptor)) { return "date"; }
            if (/time|seating/.test(descriptor)) { return "time"; }
            if (/guest|traveler|traveller|passenger|party|people|room/.test(descriptor)) { return "guest_count"; }
            if (/continue|next|search|submit|done|apply/.test(descriptor)) { return "continue"; }
            if (/reserve|book|checkout|confirm|purchase|pay/.test(descriptor)) { return "confirm"; }
            if (/tab/.test(descriptor)) { return "tab"; }
            return null;
        };
        const validationMessageFor = (element) => {
            if (!element) { return null; }
            const nativeMessage = normalize(typeof element.validationMessage === "string" ? element.validationMessage : "");
            if (nativeMessage) { return nativeMessage; }
            const describedByIds = [
                element.getAttribute?.("aria-errormessage"),
                element.getAttribute?.("aria-describedby")
            ]
                .filter(Boolean)
                .flatMap((value) => value.split(/\\s+/))
                .filter(Boolean);
            for (const id of describedByIds) {
                const describedBy = document.getElementById(id);
                const text = normalize(describedBy?.innerText || describedBy?.textContent || "");
                if (text && /required|invalid|incorrect|enter|provide|missing|error|code|phone|email|name|address/.test(text.toLowerCase())) {
                    return text;
                }
            }
            const errorNode = element.closest('label, form, section, div')?.querySelector?.('[role="alert"], [aria-live="assertive"], [aria-invalid="true"], .error, .field-error, [class*="error" i], [data-testid*="error" i], [data-test*="error" i]');
            const nearbyText = normalize(errorNode?.innerText || errorNode?.textContent || "");
            return nearbyText || null;
        };
        const actionPriority = (element, label) => {
            const descriptor = normalizeLower([
                label,
                element?.getAttribute?.("type"),
                element?.getAttribute?.("role")
            ].filter(Boolean).join(" "));
            let score = 0;
            if (/destination|where|location|from|to|city|airport/.test(descriptor)) { score += 60; }
            if (/date|calendar|arrival|departure|check-in|check out/.test(descriptor)) { score += 55; }
            if (/time|seating/.test(descriptor)) { score += 52; }
            if (/guest|traveler|traveller|passenger|party|people|room/.test(descriptor)) { score += 50; }
            if (/search|find|continue|next|submit|apply/.test(descriptor)) { score += 45; }
            if (/reserve|book|checkout|confirm|purchase|pay/.test(descriptor)) { score += 80; }
            if (element?.closest?.('form, [role="dialog"], dialog')) { score += 15; }
            if (isAuthChoiceAction(label)) { score -= 120; }
            if (isSkipNavigationAction(label) || isUtilityAction(label)) { score -= 180; }
            if ((element?.tagName?.toLowerCase?.() || "") === "select" && hasLargeSelectLabel(label)) { score -= 140; }
            if ((element?.tagName?.toLowerCase?.() || "") === "a" && /skip|jump/.test(descriptor)) { score -= 160; }
            return score;
        };
        const groupLabelFor = (element) => {
            const container = element?.closest?.('[role="tablist"], [role="radiogroup"], [role="listbox"], fieldset, form, section, nav, div');
            if (!container || container === element) { return ""; }
            return labelFor(container);
        };
        const interactiveElements = Array.from(document.querySelectorAll('input, button, select, textarea, a[href], [role="button"], [role="link"], [role="combobox"], [role="textbox"]'))
            .filter(isVisible)
            .map((element, index) => {
                const label = labelFor(element);
                return {
                    id: `element-${index}`,
                    role: element.getAttribute("role") || element.tagName.toLowerCase(),
                    label,
                    text: normalize(element.innerText || element.textContent || ""),
                    selector: selectorFor(element),
                    value: "value" in element ? element.value : null,
                    href: element.getAttribute("href"),
                    purpose: inferPurpose(element, label),
                    groupLabel: groupLabelFor(element) || null,
                    isRequired: element.required === true || element.getAttribute("aria-required") === "true",
                    isSelected: element.checked === true
                        || element.getAttribute("aria-selected") === "true"
                        || element.getAttribute("aria-checked") === "true",
                    validationMessage: validationMessageFor(element),
                    priority: actionPriority(element, label)
                };
            })
            .filter((element) => element.label && element.priority > -140)
            .sort((lhs, rhs) => rhs.priority - lhs.priority)
            .slice(0, 32);

        const hasSearchField = interactiveElements.some((element) => /search|restaurant|location|cuisine|where/i.test(element.label));

        const forms = Array.from(document.querySelectorAll('form'))
            .filter(isVisible)
            .slice(0, 6)
            .map((form, formIndex) => {
                const fields = Array.from(form.querySelectorAll('input, select, textarea, [role="combobox"], [role="textbox"]'))
                    .filter(isVisible)
                    .map((field, fieldIndex) => ({
                        id: `form-${formIndex}-field-${fieldIndex}`,
                        label: labelFor(field),
                        selector: selectorFor(field),
                        controlType: field.getAttribute("type") || field.getAttribute("role") || field.tagName.toLowerCase(),
                        value: "value" in field ? field.value : null,
                        options: field instanceof HTMLSelectElement
                            ? Array.from(field.options).map((option) => normalize(option.textContent || option.label || option.value)).filter(Boolean).slice(0, 8)
                            : [],
                        autocomplete: field.getAttribute("autocomplete"),
                        inputMode: field.getAttribute("inputmode"),
                        fieldPurpose: inferPurpose(field, labelFor(field)),
                        isRequired: field.required || field.getAttribute("aria-required") === "true",
                        isSelected: field.checked === true
                            || field.getAttribute("aria-selected") === "true"
                            || field.getAttribute("aria-checked") === "true",
                        validationMessage: validationMessageFor(field)
                    }))
                    .filter((field) => field.label || field.validationMessage || field.isRequired)
                    .sort((lhs, rhs) => {
                        const lhsScore = (lhs.isRequired ? 20 : 0) + (lhs.validationMessage ? 10 : 0);
                        const rhsScore = (rhs.isRequired ? 20 : 0) + (rhs.validationMessage ? 10 : 0);
                        return rhsScore - lhsScore;
                    })
                    .slice(0, 12);
                const submit = Array.from(form.querySelectorAll('button, input[type="submit"], [role="button"]'))
                    .filter(isVisible)[0];
                return {
                    id: `form-${formIndex}`,
                    label: labelFor(form),
                    selector: selectorFor(form),
                    submitLabel: submit ? labelFor(submit) : null,
                    fields
                };
            });

        const controlGroups = Array.from(document.querySelectorAll('[role="tablist"], [role="radiogroup"], [role="listbox"], fieldset, nav'))
            .filter(isVisible)
            .map((group, groupIndex) => {
                const role = group.getAttribute("role") || group.tagName.toLowerCase();
                const options = Array.from(group.querySelectorAll('button, [role="tab"], [role="radio"], [role="option"], a[href], input[type="radio"], input[type="checkbox"]'))
                    .filter(isVisible)
                    .slice(0, 8)
                    .map((option, optionIndex) => ({
                        id: `group-${groupIndex}-option-${optionIndex}`,
                        label: labelFor(option),
                        selector: selectorFor(option),
                        isSelected: option.getAttribute("aria-selected") === "true"
                            || option.getAttribute("aria-checked") === "true"
                            || option.checked === true
                            || option.classList?.contains?.("active") === true
                    }))
                    .filter((option) => option.label);
                return {
                    id: `group-${groupIndex}`,
                    label: labelFor(group),
                    selector: selectorFor(group),
                    kind: role,
                    options
                };
            })
            .filter((group) => group.options.length >= 2)
            .slice(0, 6);

        const resultLists = Array.from(document.querySelectorAll('ul, ol, [role="list"], section, div'))
            .filter(isVisible)
            .filter(isResultLikeContainer)
            .map((container, index) => {
                const items = Array.from(container.querySelectorAll(':scope > li, :scope > article, :scope > div, :scope > [role="listitem"], :scope > a[href]'))
                    .filter(isVisible)
                    .map((item) => normalize(item.innerText || item.textContent || ""))
                    .filter(Boolean);
                return {
                    id: `list-${index}`,
                    label: labelFor(container),
                    selector: selectorFor(container),
                    itemCount: items.length,
                    itemTitles: items.slice(0, 4)
                };
            })
            .filter((list) => list.itemCount >= 3)
            .slice(0, 4);

        const autocompleteSurfaces = Array.from(document.querySelectorAll('input[list], [role="combobox"], input[autocomplete], input'))
            .filter(isVisible)
            .map((input, index) => {
                const listId = input.getAttribute("aria-controls") || input.getAttribute("list");
                const list = listId ? document.getElementById(listId) : input.closest('[role="combobox"], form, section')?.querySelector?.('[role="listbox"], datalist, ul');
                const options = Array.from((list?.querySelectorAll?.('[role="option"], option, li, button, a[href]')) || [])
                    .filter(isVisible)
                    .map((option) => normalize(option.textContent || option.getAttribute("aria-label") || ""))
                    .filter(Boolean)
                    .slice(0, 8);
                const label = labelFor(input);
                return {
                    id: `autocomplete-${index}`,
                    label,
                    inputSelector: selectorFor(input),
                    optionSelector: list ? selectorFor(list) : null,
                    options
                };
            })
            .filter((surface) =>
                surface.options.length > 0
                || /search|destination|location|airport|city|guest|traveler|traveller|passenger/.test(surface.label.toLowerCase())
            )
            .slice(0, 6);

        const scoreCardActionCandidate = (candidate, title, subtitle) => {
            const descriptor = normalizeLower([
                labelFor(candidate),
                candidate.getAttribute?.("href"),
                candidate.getAttribute?.("aria-label"),
                candidate.getAttribute?.("title")
            ].filter(Boolean).join(" "));
            let score = 0;
            if (!descriptor) { return score; }
            if (candidate.tagName.toLowerCase() === "a") { score += 40; }
            if (/view details|details|open|select/.test(descriptor)) { score += 35; }
            if (/reserve|book|find next available/.test(descriptor)) { score += 25; }
            if (title && descriptor.includes(normalizeLower(title))) { score += 80; }
            if (subtitle && descriptor.includes(normalizeLower(subtitle))) { score += 15; }
            if (/keyboard shortcuts|map|directions|share|save|favorite|favourite|bookmark|information|info|carousel|photo|image/.test(descriptor)) {
                score -= 120;
            }
            return score;
        };

        const cards = Array.from(document.querySelectorAll('article, li, [data-test], [data-testid], section'))
            .filter(isVisible)
            .filter((element) => !isFormLikeContainer(element))
            .map((element, index) => {
                const isStandaloneControl = element.matches?.('button, a[href], input, select, textarea, [role="button"], [role="link"], [role="combobox"]');
                const formControlCount = element.querySelectorAll('input, select, textarea, [role="textbox"], [role="combobox"]').length;
                const title = normalize(
                    element.querySelector('h1, h2, h3, h4, a[href], [role="heading"]')?.textContent
                    || element.getAttribute("aria-label")
                    || ""
                );
                const subtitle = normalize(
                    element.querySelector('p, small, [data-test*="subtitle"], [data-testid*="subtitle"]')?.textContent || ""
                );
                const action = Array.from(element.querySelectorAll('a[href], button, [role="button"]'))
                    .filter((candidate) => candidate !== element)
                    .map((candidate) => ({
                        element: candidate,
                        score: scoreCardActionCandidate(candidate, title, subtitle)
                    }))
                    .filter((candidate) => candidate.score > 0)
                    .sort((lhs, rhs) => rhs.score - lhs.score)[0]?.element;
                const badgeNodes = Array.from(element.querySelectorAll('span, small, [data-test*="badge"], [data-testid*="badge"]'))
                    .map((item) => normalize(item.textContent || ""))
                    .filter(Boolean)
                    .slice(0, 3);
                return {
                    id: `card-${index}`,
                    title,
                    subtitle: subtitle || null,
                    selector: selectorFor(element),
                    actionSelector: action ? selectorFor(action) : null,
                    badges: badgeNodes,
                    isStandaloneControl: !!isStandaloneControl,
                    formControlCount
                };
            })
            .filter((card) => card.title && !card.isStandaloneControl && card.formControlCount <= 1 && (card.actionSelector || card.subtitle || card.badges.length > 0))
            .slice(0, 8);

        const dialogs = Array.from(document.querySelectorAll('[role="dialog"], dialog, [aria-modal="true"]'))
            .filter(isVisible)
            .slice(0, 3)
            .map((dialog, index) => {
                const primaryAction = Array.from(dialog.querySelectorAll('button, [role="button"], a[href]'))
                    .filter(isVisible)
                    .find((element) => /continue|next|reserve|book|confirm|done/i.test(labelFor(element)));
                const dismiss = Array.from(dialog.querySelectorAll('button, [role="button"]'))
                    .filter(isVisible)
                    .find((element) => /close|cancel|dismiss|back/i.test(labelFor(element)));
                return {
                    id: `dialog-${index}`,
                    label: labelFor(dialog),
                    selector: selectorFor(dialog),
                    primaryActionLabel: primaryAction ? labelFor(primaryAction) : null,
                    primaryActionSelector: primaryAction ? selectorFor(primaryAction) : null,
                    dismissSelector: dismiss ? selectorFor(dismiss) : null
                };
            });

        const hasDenseResults = resultLists.some((list) => list.itemCount >= 3) || cards.length >= 3;

        const datePickers = Array.from(document.querySelectorAll('input[type="date"], [role="grid"], [aria-label*="calendar" i], [data-testid*="calendar" i], [data-test*="calendar" i], table'))
            .filter(isVisible)
            .map((picker, index) => {
                const dayNodes = Array.from(picker.querySelectorAll('button, [role="gridcell"], td'))
                    .filter(isVisible)
                    .map((day) => normalize(day.textContent || day.getAttribute("aria-label") || ""))
                    .filter((value) => /(today|tomorrow|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|mon|tue|wed|thu|fri|sat|sun|^\\d{1,2}$)/i.test(value))
                    .slice(0, 14);
                const navigationActions = Array.from(picker.querySelectorAll('button, [role="button"]'))
                    .filter(isVisible)
                    .map((action) => labelFor(action))
                    .filter((label) => /next|previous|prev|month|calendar/i.test(label))
                    .slice(0, 4);
                const selectedValue = normalize(
                    picker.querySelector('[aria-selected="true"], [aria-current="date"], .selected')?.textContent
                    || picker.getAttribute("value")
                    || ""
                );
                return {
                    id: `date-picker-${index}`,
                    label: labelFor(picker),
                    selector: selectorFor(picker),
                    selectedValue: selectedValue || null,
                    visibleDays: dayNodes,
                    navigationActions
                };
            })
            .filter((picker) => picker.visibleDays.length > 0 || picker.label.toLowerCase().includes("date"))
            .slice(0, 4);

        const notices = Array.from(document.querySelectorAll('[role="alert"], [role="status"], [aria-live], .error, .success, .warning, [class*="error" i], [class*="success" i], [class*="warning" i], [data-testid*="error" i], [data-testid*="success" i], [data-testid*="warning" i], [data-test*="error" i], [data-test*="success" i], [data-test*="warning" i]'))
            .filter(isVisible)
            .map((element, index) => {
                const label = normalize(element.innerText || element.textContent || element.getAttribute("aria-label") || "");
                const descriptor = normalizeLower([
                    label,
                    element.getAttribute("role"),
                    element.getAttribute("aria-live"),
                    element.className
                ].filter(Boolean).join(" "));
                let kind = "info";
                if (/error|invalid|required|missing|failed|incorrect|expired|try again|warning/.test(descriptor)) {
                    kind = "error";
                } else if (/success|confirmed|complete|completed|placed|thank you/.test(descriptor)) {
                    kind = "success";
                }
                return {
                    id: `notice-${index}`,
                    kind,
                    label,
                    selector: selectorFor(element)
                };
            })
            .filter((notice, index, collection) =>
                notice.label
                && collection.findIndex((candidate) => candidate.kind === notice.kind && candidate.label === notice.label) === index
            )
            .slice(0, 8);

        const stepIndicators = Array.from(document.querySelectorAll('[aria-current="step"], [data-step], [data-testid*="step" i], [data-test*="step" i], [class*="step" i], [class*="progress" i], nav li, ol li'))
            .filter(isVisible)
            .map((element, index) => {
                const label = normalize(element.innerText || element.textContent || element.getAttribute("aria-label") || "");
                const descriptor = normalizeLower([
                    label,
                    element.getAttribute("aria-current"),
                    element.getAttribute("data-step"),
                    element.className
                ].filter(Boolean).join(" "));
                const isCurrent = element.getAttribute("aria-current") === "step"
                    || element.getAttribute("aria-current") === "true"
                    || element.getAttribute("aria-selected") === "true"
                    || /current|active|selected/.test(descriptor);
                return {
                    id: `step-${index}`,
                    label,
                    selector: selectorFor(element),
                    isCurrent
                };
            })
            .filter((step, index, collection) =>
                (step.isCurrent || /step|review|details|payment|shipping|confirmation|verify|guest|traveler|traveller|contact/.test(step.label.toLowerCase()))
                && collection.findIndex((candidate) => candidate.label === step.label && candidate.isCurrent === step.isCurrent) === index
            )
            .slice(0, 8);

        const primaryActions = Array.from(document.querySelectorAll('button, a[href], [role="button"], input[type="submit"]'))
            .filter(isVisible)
            .map((element, index) => {
                const label = labelFor(element);
                const labelLower = label.toLowerCase();
                let priority = 0;
                if (/search|find|continue|next/.test(labelLower)) { priority += 30; }
                if (/reserve|book|checkout|confirm|purchase/.test(labelLower)) { priority += 50; }
                if (element.closest('[role="dialog"], dialog, form')) { priority += 15; }
                if (isAuthChoiceAction(label)) { priority -= 120; }
                if (isSkipNavigationAction(label) || isUtilityAction(label)) { priority -= 180; }
                if (hasLargeSelectLabel(label)) { priority -= 140; }
                return {
                    id: `action-${index}`,
                    label,
                    selector: selectorFor(element),
                    role: element.getAttribute("role") || element.tagName.toLowerCase(),
                    priority
                };
            })
            .filter((action) => action.label && action.priority > -120)
            .sort((lhs, rhs) => rhs.priority - lhs.priority)
            .slice(0, 10);

        const reviewPageSignal = normalizeLower([
            window.location.pathname,
            document.title,
            document.querySelector('h1, h2, [role="heading"]')?.textContent
        ].filter(Boolean).join(" "));

        const transactionalBoundaries = Array.from(document.querySelectorAll('button, a[href], [role="button"], input[type="submit"]'))
            .filter(isVisible)
            .map((element, index) => {
                const label = labelFor(element);
                const labelLower = normalizeLower(label);
                const transactionalContext = labelFor(
                    element.closest('form, [role="dialog"], dialog, [data-testid*="checkout" i], [data-testid*="payment" i], [data-testid*="booking" i], [data-testid*="availability" i], [data-test*="checkout" i], [data-test*="payment" i], [data-test*="booking" i], [data-test*="availability" i], [class*="checkout" i], [class*="payment" i], [class*="booking" i], [class*="availability" i]')
                );
                const descriptor = normalizeLower([label, transactionalContext].filter(Boolean).join(" "));
                const href = normalizeLower(element.getAttribute("href") || "");
                const isLink = element.tagName.toLowerCase() === "a";
                const resultCardContainer = element.closest('[data-testid*="restaurant-card" i], [data-test*="restaurant-card" i], article, li, [role="listitem"]');
                const isPromotional = /explore restaurants|exclusive tables|new cardmembers|dining credit|sapphire reserve|learn more|see details/.test(descriptor);
                const isSavedItemAction = /save restaurant|save to favorites|save restaurant to favorites|favorite|favourite|favorites|favourites|saved items|wishlist|bookmark/.test(descriptor);
                const isDiscoveryNavigation = /view full list|view all|see all|show all|browse all|explore all|view more/.test(labelLower);
                const isAccountChoiceAction = /use email instead|continue with email|continue with phone|sign in|log in|login|verify account|verify your account|phone number/.test(labelLower);
                const isReserveForOthers = /\\b(reserve|book)\\b.*\\bfor others\\b/.test(descriptor);
                const labelHasFinalKeyword = /reserve|book|confirm|complete|purchase|pay|place order/.test(labelLower);
                const hrefHasTransactionalKeyword = /reserve|book|checkout|payment|confirm|purchase|order/.test(href);
                const hasTransactionalContainer = !!element.closest('form, [role="dialog"], dialog, [data-testid*="checkout" i], [data-test*="checkout" i], [class*="checkout" i], [class*="payment" i], [class*="booking" i]');
                const isDenseResultAction = !!resultCardContainer && hasDenseResults && !hasTransactionalContainer;
                const hasStepperKeyword = /\\bcontinue\\b|\\bnext\\b|\\bcheckout\\b/.test(descriptor);
                const hasReviewKeyword = /review(?: reservation| booking| details| step| summary)\\b|go to review|continue to review|guest details|payment details/.test(descriptor);
                const hasStrongFinalIntent = /confirm(?: reservation| booking| order)?\\b|complete(?: booking| order| reservation)?\\b|place order\\b|pay now\\b|purchase\\b|finalize(?: booking| order)?\\b|submit order\\b/.test(labelLower);
                const hasReviewPageSignal = /booking\\/details|guest details|reservation details|booking details|complete your reservation|review/.test(reviewPageSignal);
                let kind = "";
                let confidence = 0;
                if (/search|find|show results/.test(descriptor)) {
                    kind = "search_submit";
                    confidence = 50;
                } else if (
                    !isPromotional
                        && !isSavedItemAction
                        && !isDiscoveryNavigation
                        && !isAccountChoiceAction
                        && !isReserveForOthers
                        && !isDenseResultAction
                        && (labelHasFinalKeyword || hrefHasTransactionalKeyword)
                        && (hasStrongFinalIntent || hrefHasTransactionalKeyword || (hasReviewPageSignal && labelHasFinalKeyword))
                ) {
                    kind = "final_confirmation";
                    confidence = 70;
                    if (!isLink) { confidence += 15; }
                    if (hasTransactionalContainer) { confidence += 15; }
                    if (hasStrongFinalIntent) { confidence += 10; }
                    if (hasReviewPageSignal) { confidence += 15; }
                    if (isLink && /reserve|book/.test(descriptor) && !hasTransactionalContainer && !hrefHasTransactionalKeyword && !hasReviewPageSignal) {
                        confidence -= 25;
                    }
                    if (label.length > 80) { confidence -= 20; }
                } else if (/^(select|choose)\\b/.test(labelLower) || /view details\\b/.test(labelLower) || labelLower === "details") {
                    kind = "result_selection";
                    confidence = 45;
                } else if (!isDenseResultAction && (hasReviewKeyword || (hasTransactionalContainer && hasStepperKeyword))) {
                    kind = "review_step";
                    confidence = 70;
                }
                return {
                    id: `boundary-${index}`,
                    kind,
                    label,
                    selector: selectorFor(element),
                    confidence
                };
            })
            .filter((boundary) => boundary.kind)
            .sort((lhs, rhs) => rhs.confidence - lhs.confidence)
            .slice(0, 8);

        const reviewStructureSignal = forms.some((form) => {
            const haystack = normalizeLower([
                form.label,
                form.submitLabel || "",
                ...form.fields.map((field) => field.label)
            ].join(" "));
            return /review|details|phone|email|verification|occasion|special request|guest|contact|payment/.test(haystack);
        }) || notices.some((notice) => /verification|required|invalid|phone|email|reservation|guest/.test(normalizeLower(notice.label)));

        const pageStage = (() => {
            const boundaryKinds = transactionalBoundaries.map((boundary) => boundary.kind);
            if (boundaryKinds.includes("final_confirmation") && !hasDenseResults) { return "final_confirmation"; }
            if ((boundaryKinds.includes("review_step") || reviewPageSignal.includes("booking/details") || reviewPageSignal.includes("complete your reservation") || reviewStructureSignal) && !hasDenseResults) { return "review"; }
            if (dialogs.length > 0 && primaryActions.some((action) => /continue|next|done|apply/i.test(action.label))) {
                return "dialog";
            }
            if (resultLists.length > 0 || cards.length >= 2) { return "results"; }
            if (forms.length > 0 || hasSearchField) { return "form"; }
            if (primaryActions.some((action) => /search|find|show results/i.test(action.label))) { return "search"; }
            return "browse";
        })();

        const baseSemanticTargets = [
            ...interactiveElements.map((element) => ({
                id: `target-interactive-${element.id}`,
                kind: /input|textarea|select|combobox/.test(element.role) ? "field" : "action",
                label: element.label || element.text,
                selector: element.selector,
                purpose: element.purpose || null,
                groupLabel: element.groupLabel || null,
                transactionalKind: element.purpose === "confirm" ? "final_confirmation" : null,
                priority: element.priority
            })),
            ...forms.flatMap((form) => form.fields.map((field) => ({
                id: `target-form-field-${field.id}`,
                kind: "field",
                label: field.label,
                selector: field.selector,
                purpose: inferPurpose({ getAttribute: () => field.controlType }, field.label),
                groupLabel: form.label || null,
                transactionalKind: null,
                priority: /date|calendar/i.test(field.label) ? 85 : (/guest|traveler|passenger|party|room/i.test(field.label) ? 80 : 70)
            }))),
            ...autocompleteSurfaces.map((surface) => ({
                id: `target-autocomplete-${surface.id}`,
                kind: "autocomplete",
                label: surface.label,
                selector: surface.inputSelector,
                purpose: inferPurpose(null, surface.label),
                groupLabel: null,
                transactionalKind: null,
                priority: 88
            })),
            ...datePickers.map((picker) => ({
                id: `target-date-${picker.id}`,
                kind: "date_picker",
                label: picker.label,
                selector: picker.selector,
                purpose: "date",
                groupLabel: null,
                transactionalKind: null,
                priority: 92
            })),
            ...controlGroups.flatMap((group) => group.options.map((option) => ({
                id: `target-group-option-${option.id}`,
                kind: "group_option",
                label: option.label,
                selector: option.selector,
                purpose: inferPurpose(null, `${group.label} ${option.label}`),
                groupLabel: group.label || null,
                transactionalKind: null,
                priority: option.isSelected ? 40 : 82
            }))),
            ...cards.map((card) => ({
                id: `target-card-${card.id}`,
                kind: "result_card",
                label: card.title,
                selector: card.actionSelector || card.selector,
                purpose: "result",
                groupLabel: card.subtitle || null,
                transactionalKind: "result_selection",
                priority: 68
            })),
            ...primaryActions.map((action) => ({
                id: `target-primary-${action.id}`,
                kind: "primary_action",
                label: action.label,
                selector: action.selector,
                purpose: inferPurpose(null, action.label),
                groupLabel: null,
                transactionalKind: transactionalBoundaries.find((boundary) => boundary.selector === action.selector)?.kind || null,
                priority: action.priority + 10
            })),
            ...dialogs.flatMap((dialog) => {
                const targets = [];
                if (dialog.primaryActionSelector) {
                    targets.push({
                        id: `target-dialog-primary-${dialog.id}`,
                        kind: "dialog_action",
                        label: dialog.primaryActionLabel || dialog.label,
                        selector: dialog.primaryActionSelector,
                        purpose: inferPurpose(null, `${dialog.label} ${dialog.primaryActionLabel || ""}`),
                        groupLabel: dialog.label || null,
                        transactionalKind: transactionalBoundaries.find((boundary) => boundary.selector === dialog.primaryActionSelector)?.kind || null,
                        priority: 96
                    });
                }
                if (dialog.dismissSelector) {
                    targets.push({
                        id: `target-dialog-dismiss-${dialog.id}`,
                        kind: "dialog_dismiss",
                        label: `${dialog.label} dismiss`,
                        selector: dialog.dismissSelector,
                        purpose: "dismiss",
                        groupLabel: dialog.label || null,
                        transactionalKind: null,
                        priority: 64
                    });
                }
                return targets;
            })
        ]
            .filter((target) => target.label && target.selector);

        const bookingPartyOptions = Array.from(document.querySelectorAll('select option, [role="option"], button, [role="button"]'))
            .filter(isVisible)
            .map((element) => normalize(element.textContent || element.getAttribute("aria-label") || ""))
            .filter((label) => /\\b\\d+\\b/.test(label) && /(people|guest|party|table for)/i.test(label))
            .slice(0, 8);
        const bookingDateOptions = Array.from(document.querySelectorAll('button, [role="button"], td, [role="gridcell"], [role="option"]'))
            .filter(isVisible)
            .map((element) => normalize(element.textContent || element.getAttribute("aria-label") || ""))
            .filter((label) => /(today|tomorrow|mon|tue|wed|thu|fri|sat|sun|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|\\d{1,2})/i.test(label))
            .slice(0, 10);
        const bookingTimeOptions = Array.from(document.querySelectorAll('button, [role="button"], [role="option"], option, a[href]'))
            .filter(isVisible)
            .map((element) => normalize(element.textContent || element.getAttribute("aria-label") || ""))
            .filter((label) => /\\b\\d{1,2}(:\\d{2})?\\s?(am|pm)\\b/i.test(label))
            .slice(0, 12);
        const availableSlots = Array.from(document.querySelectorAll('button, a[href], [role="button"], [role="link"]'))
            .filter(isVisible)
            .map((element, index) => {
                const label = normalize(element.textContent || element.getAttribute("aria-label") || "");
                const nearby = normalize(element.closest('article, li, [role="dialog"], dialog, section, div')?.textContent || "");
                const transactionalSlotContainer = element.closest('form, [role="dialog"], dialog, [data-testid*="booking" i], [data-testid*="availability" i], [data-testid*="reservation" i], [data-test*="booking" i], [data-test*="availability" i], [data-test*="reservation" i], [class*="booking" i], [class*="availability" i], [class*="reservation" i]');
                const slotGroupContainer = element.closest('[data-testid*="time" i], [data-testid*="slot" i], [data-testid*="availability" i], [data-test*="time" i], [data-test*="slot" i], [data-test*="availability" i], [class*="time" i], [class*="slot" i], [class*="availability" i], section, div');
                const slotGroupText = normalize(slotGroupContainer?.textContent || "");
                const resultCardContainer = element.closest('[data-testid*="restaurant-card" i], [data-test*="restaurant-card" i], article, li, [role="listitem"]');
                const isDenseResultSlot = !!resultCardContainer && hasDenseResults && !transactionalSlotContainer;
                const hasTimeLikeLabel = /\\b\\d{1,2}(:\\d{2})?\\s?(am|pm)\\b/i.test(label);
                const hasReserveTableLabel = /reserve table at|book table at|reserve at/.test(label);
                const hasSelectTimeContext = /select a time|available times?|choose a time|pick a time/.test(slotGroupText);
                const inlineTimeButtonCount = slotGroupContainer
                    ? Array.from(slotGroupContainer.querySelectorAll('button, [role="button"], a[href], [role="link"]'))
                        .filter(isVisible)
                        .map((candidate) => normalize(candidate.textContent || candidate.getAttribute("aria-label") || ""))
                        .filter((candidateLabel) => /\\b\\d{1,2}(:\\d{2})?\\s?(am|pm)\\b/i.test(candidateLabel))
                        .length
                    : 0;
                let score = 0;
                if (hasTimeLikeLabel) { score += 70; }
                if (/reserve|book/i.test(nearby)) { score += 20; }
                if (transactionalSlotContainer) { score += 20; }
                if (hasReserveTableLabel) { score += 40; }
                if (hasSelectTimeContext) { score += 35; }
                if (inlineTimeButtonCount >= 2) { score += 25; }
                if (isDenseResultSlot) { score -= 120; }
                if (!hasTimeLikeLabel && !hasReserveTableLabel) { score -= 120; }
                if (/sold out|waitlist|notify/i.test(`${label} ${nearby}`)) { score -= 100; }
                return {
                    id: `slot-${index}`,
                    label,
                    selector: selectorFor(element),
                    score
                };
            })
            .filter((slot) => slot.score > 0)
            .sort((lhs, rhs) => rhs.score - lhs.score)
            .slice(0, 10);
        const confirmationButtons = primaryActions
            .map((action) => action.label)
            .filter((label) => /reserve|book|confirm|complete|checkout/i.test(label))
            .slice(0, 6);
        const semanticTargets = [
            ...baseSemanticTargets,
            ...availableSlots.map((slot) => ({
                id: `target-${slot.id}`,
                kind: "slot_option",
                label: slot.label,
                selector: slot.selector,
                purpose: "time",
                groupLabel: "available reservation slots",
                transactionalKind: "booking_slot",
                priority: 118 + Math.min(slot.score, 40)
            }))
        ]
            .filter((target) => target.label && target.selector)
            .sort((lhs, rhs) => rhs.priority - lhs.priority)
            .slice(0, 40);

        const semanticFieldValues = [
            ...interactiveElements.map((element) => ({
                label: normalizeLower(element.label),
                value: normalizeLower(element.value || element.text || ""),
                purpose: element.purpose || ""
            })),
            ...forms.flatMap((form) => form.fields.map((field) => ({
                label: normalizeLower(field.label),
                value: normalizeLower(field.value || ""),
                purpose: inferPurpose({ getAttribute: () => field.controlType }, field.label) || ""
            }))),
            ...controlGroups.flatMap((group) =>
                group.options
                    .filter((option) => option.isSelected)
                    .map((option) => ({
                        label: normalizeLower(`${group.label} ${option.label}`),
                        value: normalizeLower(option.label),
                        purpose: inferPurpose(null, `${group.label} ${option.label}`) || ""
                    }))
            ),
            ...datePickers.map((picker) => ({
                label: normalizeLower(picker.label),
                value: normalizeLower(picker.selectedValue || ""),
                purpose: "date"
            }))
        ];
        const hasMeaningfulValue = (value) =>
            !!value
                && !/^(select|choose|all day|any time|date|time|party size|guests?|people)$/i.test(value);
        const selectedPartySize = semanticFieldValues.some((entry) =>
            (entry.purpose === "guest_count"
                || /guest|party|people|person|table for|traveler|traveller|passenger|room/.test(entry.label))
            && /\\b\\d+\\b/.test(entry.value)
        );
        const selectedDate = semanticFieldValues.some((entry) =>
            (entry.purpose === "date" || /date|calendar|check-in|checkout|arrival|departure/.test(entry.label))
            && hasMeaningfulValue(entry.value)
        );
        const selectedTime = semanticFieldValues.some((entry) =>
            (/time|seating/.test(entry.label) && /\\b\\d{1,2}(:\\d{2})?\\s?(am|pm)\\b/i.test(entry.value))
                || (/\\b\\d{1,2}(:\\d{2})?\\s?(am|pm)\\b/i.test(entry.label) && hasMeaningfulValue(entry.value) && entry.value.length <= 24)
        );
        const bookingFieldLabels = [
            ...forms.flatMap((form) => form.fields.map((field) => field.label)),
            ...interactiveElements.map((element) => element.label),
            ...controlGroups.map((group) => group.label),
            ...autocompleteSurfaces.map((surface) => surface.label),
            ...datePickers.map((picker) => picker.label)
        ]
            .map(normalizeLower)
            .filter(Boolean);
        const hasPartyControl = bookingFieldLabels.some((label) => /guest|party|people|person|table for|traveler|traveller|passenger|room/.test(label))
            || bookingPartyOptions.length > 0;
        const hasDateControl = bookingFieldLabels.some((label) => /date|calendar|check-in|checkout|arrival|departure/.test(label))
            || datePickers.length > 0
            || bookingDateOptions.length > 0;
        const hasTimeControl = bookingFieldLabels.some((label) => /time|seating/.test(label))
            || bookingTimeOptions.length > 0;
        const hasBookingWidget = (hasPartyControl && hasDateControl) || (hasDateControl && hasTimeControl) || (hasPartyControl && hasTimeControl);
        const guestDetailFieldCount = forms.reduce((total, form) => total + form.fields.filter((field) =>
            /name|email|phone|contact|special request|occasion|notes?|guest/.test(field.label.toLowerCase())
        ).length, 0);
        const paymentFieldCount = forms.reduce((total, form) => total + form.fields.filter((field) =>
            /card|credit|debit|payment|billing|cvv|security code|expiry|exp date/.test(field.label.toLowerCase())
        ).length, 0);
        const reviewSignalLabels = [
            ...forms.map((form) => form.label),
            ...dialogs.map((dialog) => dialog.label),
            ...primaryActions.map((action) => action.label),
            ...transactionalBoundaries.map((boundary) => boundary.label)
        ]
            .map(normalizeLower)
            .filter(Boolean);
        const hasReviewSummary = reviewSignalLabels.some((label) =>
            /review(?: reservation| booking| details| summary| step)|trip details|booking details|reservation details|order summary|guest details|payment details/.test(label)
        ) || transactionalBoundaries.some((boundary) => boundary.kind === "review_step");
        const hasVenueAction = primaryActions.some((action) => /reserve|book/i.test(action.label))
            || transactionalBoundaries.some((boundary) => /reserve|book/i.test(boundary.label.toLowerCase()));
        const hasFinalConfirmationBoundary = transactionalBoundaries.some((boundary) => boundary.kind === "final_confirmation");
        const selectedParameterCount = [selectedPartySize, selectedDate, selectedTime].filter(Boolean).length;
        const hasLateStageBookingStructure = paymentFieldCount > 0 || hasReviewSummary || guestDetailFieldCount >= 2 || availableSlots.length > 0;
        const bookingFunnelStage = (() => {
            if (hasFinalConfirmationBoundary && hasLateStageBookingStructure && !hasDenseResults) {
                return "final_confirmation";
            }
            if (paymentFieldCount > 0 || hasReviewSummary) {
                return "review";
            }
            if (guestDetailFieldCount >= 2) {
                return "guest_details";
            }
            if (availableSlots.length > 0) {
                return "slot_selection";
            }
            if (pageStage === "results" || hasDenseResults) {
                return "results";
            }
            if (hasBookingWidget || selectedParameterCount > 0) {
                return "booking_widget";
            }
            if (hasVenueAction && cards.length <= 1) {
                return "venue_detail";
            }
            if (pageStage === "form" || pageStage === "search" || hasSearchField) {
                return "search";
            }
            return "browse";
        })();
        const hasBookingSignals = hasVenueAction
            || hasBookingWidget
            || availableSlots.length > 0
            || guestDetailFieldCount > 0
            || paymentFieldCount > 0
            || hasReviewSummary
            || hasFinalConfirmationBoundary
            || selectedParameterCount > 0
            || /opentable|booking\\.com|travel|flight|resy|airbnb/.test(location.hostname);
        const booking = hasBookingSignals
            ? {
                partySizeOptions: bookingPartyOptions,
                dateOptions: bookingDateOptions,
                timeOptions: bookingTimeOptions,
                availableSlots,
                confirmationButtons
            }
            : null;
        const bookingFunnel = hasBookingSignals
            ? {
                stage: bookingFunnelStage,
                selectedParameterCount,
                hasVenueAction,
                hasBookingWidget,
                hasSlotSelection: availableSlots.length > 0,
                hasGuestDetailsForm: guestDetailFieldCount >= 2,
                hasPaymentForm: paymentFieldCount > 0,
                hasReviewSummary,
                hasFinalConfirmationBoundary,
                selectedDate,
                selectedTime,
                selectedPartySize
            }
            : null;

        return {
            title: document.title,
            url: location.href,
            pageStage,
            formCount: document.forms.length,
            hasSearchField,
            interactiveElements,
            forms,
            resultLists,
            cards,
            dialogs,
            controlGroups,
            autocompleteSurfaces,
            datePickers,
            notices,
            stepIndicators,
            primaryActions,
            transactionalBoundaries,
            semanticTargets,
            booking,
            bookingFunnel
        };
        """

    static func resultsProbe(expectedText: String?) -> String {
        let expectedTextLiteral = expectedText.map(jsStringLiteral) ?? "null"
        return """
        const expectedText = (\(expectedTextLiteral) || "").replace(/\\s+/g, " ").trim().toLowerCase();
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim();
        const normalizeLower = (value) => normalize(value).toLowerCase();
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const cards = Array.from(document.querySelectorAll('article, li, [role="listitem"], [data-testid], [data-test], section'))
            .filter(isVisible)
            .map((element) => normalize(
                element.querySelector('h1, h2, h3, h4, [role="heading"], a[href]')?.textContent
                || element.getAttribute("aria-label")
                || ""
            ))
            .filter(Boolean);
        const lists = Array.from(document.querySelectorAll('ul, ol, [role="list"]'))
            .filter(isVisible)
            .map((list) => Array.from(list.querySelectorAll(':scope > li, :scope > [role="listitem"], :scope > article, :scope > div'))
                .filter(isVisible)
                .map((item) => normalize(item.textContent || ""))
                .filter(Boolean))
            .filter((items) => items.length >= 2);
        const bodyText = normalizeLower(document.body ? document.body.innerText : "");
        const textMatchCount = expectedText && bodyText.includes(expectedText) ? 1 : 0;
        const resultCount = Math.max(cards.length, lists.reduce((sum, list) => sum + list.length, 0));
        return {
            url: window.location.href,
            title: document.title,
            found: resultCount >= 2 || lists.length > 0 || textMatchCount > 0,
            resultCount,
            cardCount: cards.length,
            listCount: lists.length,
            textMatchCount,
            firstResultTitle: cards[0] || lists[0]?.[0] || null
        };
        """
    }

    static func dialogProbe(expectedText: String?) -> String {
        let expectedTextLiteral = expectedText.map(jsStringLiteral) ?? "null"
        return """
        const expectedText = (\(expectedTextLiteral) || "").replace(/\\s+/g, " ").trim().toLowerCase();
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim();
        const normalizeLower = (value) => normalize(value).toLowerCase();
        const isVisible = (element) => {
            if (!element) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none"
                && style.visibility !== "hidden"
                && rect.width > 1
                && rect.height > 1;
        };
        const labelFor = (element) => normalize([
            element?.getAttribute?.("aria-label"),
            element?.querySelector?.("h1, h2, h3, h4, [role='heading']")?.textContent,
            element?.innerText,
            element?.textContent
        ].filter(Boolean).join(" "));
        const dialogs = Array.from(document.querySelectorAll('[role="dialog"], dialog, [aria-modal="true"]'))
            .filter(isVisible)
            .map((dialog) => ({
                element: dialog,
                label: labelFor(dialog)
            }));
        const matched = dialogs.find((dialog) => !expectedText || normalizeLower(dialog.label).includes(expectedText)) || dialogs[0];
        return {
            url: window.location.href,
            title: document.title,
            found: !!matched,
            label: matched ? matched.label : "",
            selector: matched && matched.element.id ? `#${matched.element.id}` : ""
        };
        """
    }

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
                    || label.includes("result")
                    || label.includes("details");
            }).length;
        const hasDialog = Array.from(document.querySelectorAll('[role="dialog"], dialog, [aria-modal="true"]'))
            .filter(isVisible).length > 0;
        return {
            url: window.location.href,
            title: document.title,
            readyState: document.readyState,
            visibleResultCount: resultCount,
            hasDialog
        };
        """
    }

    static func visibleTextProbe(_ text: String) -> String {
        let textLiteral = jsStringLiteral(text.lowercased())
        return """
        const targetText = \(textLiteral);
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim();
        const bodyText = normalize(document.body ? document.body.innerText : "");
        const lowered = bodyText.toLowerCase();
        const index = lowered.indexOf(targetText);
        const firstMatch = index >= 0 ? bodyText.slice(index, index + targetText.length + 80) : "";
        const matchCount = targetText ? lowered.split(targetText).length - 1 : 0;
        return {
            url: window.location.href,
            title: document.title,
            matchCount,
            firstMatch
        };
        """
    }

    static func selectOpenTablePartySize(_ partySize: Int) -> String {
        let optionText = jsStringLiteral("\(partySize)")
        return """
        const target = \(optionText);
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim().toLowerCase();
        const selects = Array.from(document.querySelectorAll('select'))
            .filter((element) => normalize(element.getAttribute("aria-label") || element.name || "").includes("party")
                || normalize(element.closest("form, section, div")?.innerText || "").includes("party size"));
        for (const select of selects) {
            const option = Array.from(select.options).find((candidate) => normalize(candidate.textContent || candidate.label || candidate.value).includes(target));
            if (option) {
                select.value = option.value;
                select.dispatchEvent(new Event("input", { bubbles: true }));
                select.dispatchEvent(new Event("change", { bubbles: true }));
                return { label: option.textContent || option.label || option.value };
            }
        }
        const buttons = Array.from(document.querySelectorAll('button, [role="button"], [role="option"]'));
        const match = buttons.find((button) => {
            const label = normalize(button.textContent || button.getAttribute("aria-label") || "");
            return label.includes(target) && /(party|people|guest|table for)/.test(label);
        });
        if (!match) {
            throw new Error(`No OpenTable party size option matched ${target}.`);
        }
        match.click();
        return { label: match.textContent || match.getAttribute("aria-label") || "" };
        """
    }

    static func selectOpenTableDate(_ dateText: String) -> String {
        let targetLiteral = jsStringLiteral(dateText.lowercased())
        return """
        const target = \(targetLiteral);
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim().toLowerCase();
        const controls = Array.from(document.querySelectorAll('button, [role="button"], [role="gridcell"], td, input'));
        const match = controls.find((element) => {
            const label = normalize(element.textContent || element.getAttribute("aria-label") || element.value || "");
            return label.includes(target);
        });
        if (!match) {
            throw new Error(`No OpenTable date matched ${target}.`);
        }
        match.click?.();
        return { label: match.textContent || match.getAttribute("aria-label") || match.value || "" };
        """
    }

    static func selectOpenTableTime(_ timeText: String) -> String {
        let targetLiteral = jsStringLiteral(timeText.lowercased())
        return """
        const target = \(targetLiteral);
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim().toLowerCase();
        const select = Array.from(document.querySelectorAll('select')).find((element) =>
            normalize(element.getAttribute("aria-label") || element.name || "").includes("time")
        );
        if (select) {
            const option = Array.from(select.options).find((candidate) => normalize(candidate.textContent || candidate.label || candidate.value).includes(target));
            if (option) {
                select.value = option.value;
                select.dispatchEvent(new Event("input", { bubbles: true }));
                select.dispatchEvent(new Event("change", { bubbles: true }));
                return { label: option.textContent || option.label || option.value };
            }
        }
        const buttons = Array.from(document.querySelectorAll('button, [role="button"], [role="option"], a[href]'));
        const match = buttons.find((button) => normalize(button.textContent || button.getAttribute("aria-label") || "").includes(target));
        if (!match) {
            throw new Error(`No OpenTable time matched ${target}.`);
        }
        match.click();
        return { label: match.textContent || match.getAttribute("aria-label") || "" };
        """
    }

    static func clickBestOpenTableSlot(preferredTime: String?) -> String {
        let preferredLiteral = jsStringLiteral((preferredTime ?? "").lowercased())
        return """
        const preferredTime = \(preferredLiteral);
        const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim().toLowerCase();
        const slots = Array.from(document.querySelectorAll('button, a[href], [role="button"], [role="link"]'))
            .map((element) => {
                const label = normalize(element.textContent || element.getAttribute("aria-label") || "");
                const nearby = normalize(element.closest('article, li, [role="dialog"], dialog, section, div')?.textContent || "");
                let score = 0;
                if (/\\b\\d{1,2}(:\\d{2})?\\s?(am|pm)\\b/.test(label)) { score += 70; }
                if (preferredTime && label.includes(preferredTime)) { score += 30; }
                if (/reserve|book/.test(nearby)) { score += 20; }
                if (/sold out|waitlist|notify/.test(`${label} ${nearby}`)) { score -= 100; }
                return { element, label, score };
            })
            .filter((slot) => slot.score > 0)
            .sort((lhs, rhs) => rhs.score - lhs.score);
        const slot = slots[0];
        if (!slot) {
            throw new Error("No OpenTable reservation slot was available.");
        }
        slot.element.click();
        return { label: slot.label };
        """
    }

    nonisolated private static func jsStringLiteral(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return String(data: data ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
    }
}
