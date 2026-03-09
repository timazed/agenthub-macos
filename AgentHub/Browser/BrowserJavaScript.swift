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
        throw new Error(`Element matched by ${selector} is not a native select element.`);
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
            if (normalizedValue === normalizedTarget) { return 140; }
            if (normalizedValue.includes(normalizedTarget)) { return 110; }
            if (/^\\d{1,2}$/.test(normalizedTarget) && normalizedValue === normalizedTarget) { return 100; }
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
                const label = normalize(element.getAttribute("aria-label") || element.textContent || "");
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
        const labelFor = (element) => normalize([
            element?.getAttribute?.("aria-label"),
            element?.getAttribute?.("placeholder"),
            element?.getAttribute?.("name"),
            element?.id,
            element?.innerText,
            element?.textContent
        ].filter(Boolean).join(" "));
        const inferPurpose = (element, label) => {
            const descriptor = normalizeLower([
                label,
                element?.getAttribute?.("type"),
                element?.getAttribute?.("role"),
                element?.getAttribute?.("autocomplete"),
                element?.getAttribute?.("inputmode")
            ].filter(Boolean).join(" "));
            if (/destination|where|location|from|to|city|airport/.test(descriptor)) { return "location"; }
            if (/search|find|look up/.test(descriptor)) { return "search"; }
            if (/date|calendar|check-in|check out|checkout|arrival|departure/.test(descriptor)) { return "date"; }
            if (/guest|traveler|traveller|passenger|party|people|room/.test(descriptor)) { return "guest_count"; }
            if (/continue|next|search|submit|done|apply/.test(descriptor)) { return "continue"; }
            if (/reserve|book|checkout|confirm|purchase|pay/.test(descriptor)) { return "confirm"; }
            if (/tab/.test(descriptor)) { return "tab"; }
            return null;
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
            if (/guest|traveler|traveller|passenger|party|people|room/.test(descriptor)) { score += 50; }
            if (/search|find|continue|next|submit|apply/.test(descriptor)) { score += 45; }
            if (/reserve|book|checkout|confirm|purchase|pay/.test(descriptor)) { score += 80; }
            if (element?.closest?.('form, [role="dialog"], dialog')) { score += 15; }
            return score;
        };
        const groupLabelFor = (element) => {
            const container = element?.closest?.('[role="tablist"], [role="radiogroup"], [role="listbox"], fieldset, form, section, nav, div');
            if (!container || container === element) { return ""; }
            return labelFor(container);
        };
        const interactiveElements = Array.from(document.querySelectorAll('input, button, select, textarea, a[href], [role="button"], [role="link"], [role="combobox"]'))
            .filter(isVisible)
            .slice(0, 24)
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
                    priority: actionPriority(element, label)
                };
            })
            .sort((lhs, rhs) => rhs.priority - lhs.priority);

        const hasSearchField = interactiveElements.some((element) => /search|restaurant|location|cuisine|where/i.test(element.label));

        const forms = Array.from(document.querySelectorAll('form'))
            .filter(isVisible)
            .slice(0, 6)
            .map((form, formIndex) => {
                const fields = Array.from(form.querySelectorAll('input, select, textarea, [role="combobox"]'))
                    .filter(isVisible)
                    .slice(0, 8)
                    .map((field, fieldIndex) => ({
                        id: `form-${formIndex}-field-${fieldIndex}`,
                        label: labelFor(field),
                        selector: selectorFor(field),
                        controlType: field.getAttribute("type") || field.getAttribute("role") || field.tagName.toLowerCase(),
                        value: "value" in field ? field.value : null,
                        options: field instanceof HTMLSelectElement
                            ? Array.from(field.options).map((option) => normalize(option.textContent || option.label || option.value)).filter(Boolean).slice(0, 8)
                            : [],
                        isRequired: field.required || field.getAttribute("aria-required") === "true"
                    }));
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

        const cards = Array.from(document.querySelectorAll('article, li, [data-test], [data-testid], section'))
            .filter(isVisible)
            .map((element, index) => {
                const title = normalize(
                    element.querySelector('h1, h2, h3, h4, a[href], [role="heading"]')?.textContent
                    || element.getAttribute("aria-label")
                    || ""
                );
                const subtitle = normalize(
                    element.querySelector('p, small, [data-test*="subtitle"], [data-testid*="subtitle"]')?.textContent || ""
                );
                const action = element.querySelector('a[href], button, [role="button"]');
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
                    badges: badgeNodes
                };
            })
            .filter((card) => card.title)
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

        const primaryActions = Array.from(document.querySelectorAll('button, a[href], [role="button"], input[type="submit"]'))
            .filter(isVisible)
            .map((element, index) => {
                const label = labelFor(element);
                const labelLower = label.toLowerCase();
                let priority = 0;
                if (/search|find|continue|next/.test(labelLower)) { priority += 30; }
                if (/reserve|book|checkout|confirm|purchase/.test(labelLower)) { priority += 50; }
                if (element.closest('[role="dialog"], dialog, form')) { priority += 15; }
                return {
                    id: `action-${index}`,
                    label,
                    selector: selectorFor(element),
                    role: element.getAttribute("role") || element.tagName.toLowerCase(),
                    priority
                };
            })
            .filter((action) => action.label)
            .sort((lhs, rhs) => rhs.priority - lhs.priority)
            .slice(0, 10);

        const transactionalBoundaries = Array.from(document.querySelectorAll('button, a[href], [role="button"], input[type="submit"]'))
            .filter(isVisible)
            .map((element, index) => {
                const label = labelFor(element);
                const descriptor = normalizeLower([
                    label,
                    labelFor(element.closest('form, [role="dialog"], dialog, section, article'))
                ].filter(Boolean).join(" "));
                const href = normalizeLower(element.getAttribute("href") || "");
                const isLink = element.tagName.toLowerCase() === "a";
                const isPromotional = /explore restaurants|exclusive tables|new cardmembers|dining credit|sapphire reserve|learn more|see details/.test(descriptor);
                const hasTransactionalContainer = !!element.closest('form, [role="dialog"], dialog, [data-testid*="checkout" i], [data-test*="checkout" i], [class*="checkout" i], [class*="payment" i], [class*="booking" i]');
                let kind = "";
                let confidence = 0;
                if (/search|find|show results/.test(descriptor)) {
                    kind = "search_submit";
                    confidence = 50;
                } else if (/select|choose|view details|details/.test(descriptor)) {
                    kind = "result_selection";
                    confidence = 45;
                } else if (/continue|next|review|checkout/.test(descriptor)) {
                    kind = "review_step";
                    confidence = 70;
                } else if (!isPromotional && /reserve|book|confirm|complete|purchase|pay|place order/.test(descriptor)) {
                    kind = "final_confirmation";
                    confidence = 70;
                    if (!isLink) { confidence += 15; }
                    if (hasTransactionalContainer) { confidence += 15; }
                    if (/confirm|purchase|pay|place order|complete booking/.test(descriptor)) { confidence += 10; }
                    if (isLink && /reserve|book/.test(descriptor) && !hasTransactionalContainer && !/reserve|book|checkout|payment|confirm/.test(href)) {
                        confidence -= 25;
                    }
                    if (label.length > 80) { confidence -= 20; }
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

        const pageStage = (() => {
            const boundaryKinds = transactionalBoundaries.map((boundary) => boundary.kind);
            if (boundaryKinds.includes("final_confirmation")) { return "final_confirmation"; }
            if (boundaryKinds.includes("review_step")) { return "review"; }
            if (dialogs.length > 0 && primaryActions.some((action) => /continue|next|done|apply/i.test(action.label))) {
                return "dialog";
            }
            if (resultLists.length > 0 || cards.length >= 2) { return "results"; }
            if (forms.length > 0 || hasSearchField) { return "form"; }
            if (primaryActions.some((action) => /search|find|show results/i.test(action.label))) { return "search"; }
            return "browse";
        })();

        const semanticTargets = [
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
            .filter((target) => target.label && target.selector)
            .sort((lhs, rhs) => rhs.priority - lhs.priority)
            .slice(0, 40);

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
                let score = 0;
                if (/\\b\\d{1,2}(:\\d{2})?\\s?(am|pm)\\b/i.test(label)) { score += 70; }
                if (/reserve|book/i.test(nearby)) { score += 20; }
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

        const booking = location.hostname.includes("opentable")
            ? {
                partySizeOptions: bookingPartyOptions,
                dateOptions: bookingDateOptions,
                timeOptions: bookingTimeOptions,
                availableSlots,
                confirmationButtons
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
            primaryActions,
            transactionalBoundaries,
            semanticTargets,
            booking
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
