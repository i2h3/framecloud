/* ==========================================================================
   Cirruscope — site behaviour
   Localised copy lives in dedicated pages under /de/, /fr/ and /es/ (English
   at the root), so translations are fully static and crawlable. This script
   only handles progressive enhancements:
     - first-visit language redirect (from the English pages only) based on a
       remembered choice or the browser language;
     - the language menu, mobile navigation and the FAQ accordion.
   Dark/light appearance is handled entirely in CSS via prefers-color-scheme.
   ========================================================================== */
(function () {
  "use strict";

  var SUPPORTED = ["en", "de", "fr", "es"];
  var STORAGE_KEY = "cirruscope-lang";

  function currentLang() {
    return document.documentElement.lang || "en";
  }

  function preferredLang() {
    try {
      var saved = localStorage.getItem(STORAGE_KEY);
      if (saved && SUPPORTED.indexOf(saved) !== -1) return saved;
    } catch (e) {}
    var nav = (navigator.language || "en").slice(0, 2).toLowerCase();
    return SUPPORTED.indexOf(nav) !== -1 ? nav : "en";
  }

  // Redirect first-time visitors from the English pages to their language.
  function maybeRedirect() {
    if (currentLang() !== "en") return;
    // Some pages are English-only, so never auto-redirect away from them.
    if (document.body.hasAttribute("data-no-lang-redirect")) return;
    try {
      if (sessionStorage.getItem("cirruscope-redirected")) return;
    } catch (e) {}
    var target = preferredLang();
    if (target === "en") return;
    var link = document.querySelector('.lang__option[data-lang="' + target + '"]');
    if (!link) return;
    var href = link.getAttribute("href");
    if (!href) return;
    try {
      sessionStorage.setItem("cirruscope-redirected", "1");
    } catch (e) {}
    window.location.replace(href);
  }

  function initLanguageMenu() {
    var toggle = document.querySelector(".lang__button");
    var menu = document.querySelector(".lang__menu");
    if (!toggle || !menu) return;

    function close() {
      menu.hidden = true;
      toggle.setAttribute("aria-expanded", "false");
    }
    function open() {
      menu.hidden = false;
      toggle.setAttribute("aria-expanded", "true");
    }

    toggle.addEventListener("click", function (e) {
      e.stopPropagation();
      if (menu.hidden) open();
      else close();
    });
    menu.querySelectorAll(".lang__option").forEach(function (opt) {
      opt.addEventListener("click", function () {
        try {
          localStorage.setItem(STORAGE_KEY, opt.getAttribute("data-lang"));
        } catch (e) {}
      });
    });
    document.addEventListener("click", function (e) {
      if (!menu.hidden && !menu.contains(e.target) && e.target !== toggle) close();
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") close();
    });
  }

  function initMobileNav() {
    var toggle = document.querySelector(".hamburger");
    var nav = document.getElementById("mobile-nav");
    if (!toggle || !nav) return;
    toggle.addEventListener("click", function () {
      nav.hidden = !nav.hidden;
      toggle.setAttribute("aria-expanded", nav.hidden ? "false" : "true");
    });
  }

  function initFaq() {
    var questions = document.querySelectorAll(".faq__question");
    questions.forEach(function (btn) {
      var item = btn.closest(".faq__item");
      var answer = item.querySelector(".faq__answer");
      var sign = btn.querySelector(".faq__sign");
      btn.addEventListener("click", function () {
        var willOpen = answer.hidden;
        document.querySelectorAll(".faq__answer").forEach(function (a) { a.hidden = true; });
        document.querySelectorAll(".faq__question").forEach(function (q) {
          q.setAttribute("aria-expanded", "false");
          var s = q.querySelector(".faq__sign");
          if (s) s.textContent = "+";
        });
        if (willOpen) {
          answer.hidden = false;
          btn.setAttribute("aria-expanded", "true");
          if (sign) sign.textContent = "\u00d7";
        }
      });
    });
  }

  function init() {
    maybeRedirect();
    initLanguageMenu();
    initMobileNav();
    initFaq();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
