---
layout: post
title: Counting nodes quickly with XSLT keys
tags: xslt, performance
---

Pretty much everyone who has written any non-trivial XSLT code knows that the answer to most XSLT performance problems is keys. In this article, we'll first take a look at how XSLT keys work. Then we'll move onto an example on how to use keys to count things fast.

*Note*: You need XPath 2 to use the technique in this article.

*For a tl;dr, jump to the [Conclusion](#conclusion)*.

## An introduction to keys

Keys are a mechanism that build an index from a value to a set of nodes in the XML tree. The term *key* might be a bit confusing. You can usually think of it as a key-value pair like any other (map, hash, dictionary, table, what have you). So maybe it should have been called *index* instead of *key*.

Here’s a simple example of using a key:

{% highlight xml %}
<!-- input.xml -->

<sect id="s2">
  <sect id="s2-1"> ... </sect>
  <sect id="s2-2"> ... </sect>
</sect>

<!-- stylesheet.xsl -->

<!--
Create a key called "id".
Put every element that has an @id attribute in it.
Use the value of the @id attribute as the, well, *key* of the entry.
-->
<xsl:key name="id" match="*[@id]" use="@id"/>

<xsl:template match="/">
  <!--
  Fetch the element with the @id attribute value "s2-2", no matter
  where in the input document it is.
  -->
  <xsl:sequence select="key('id', 's2-2')"/>
</xsl:template>
{% endhighlight %}

You can visualize the `id` key like this:

```
"s2"   => <sect id="s2"/>
"s2-1" => <sect id="s2-1"/>
"s2-2" => <sect id="s2-2"/>
```

Creating a key takes a small amount of time. Once created, though, accessing nodes in the key is usually much faster than doing it without keys.

For example, to get to `<sect id="s2-2">` without keys, you'd do something like this:

{% highlight xml %}
<xsl:sequence select="//sect[@id eq 's2-2']"/>
{% endhighlight %}

If you do that, your XSLT processor will have to sift through the entire XML tree to find the element whose ID is `s2-2`. If you use the key, the processor only needs to look up the value `s2-2` in the index. That's *much* faster.

Keys are also lazy. That means they're only created when you first call the `key()` function on a key. That way there's no performance penalty if you create a key but don't end up using it.

## Using keys to count things quickly

It's pretty common to have count things in your XSLT code.

For example, take [this big DocBook XML file][docbook-guide]. It has many tables like this:

{% highlight xml %}
<informaltable role="elemsynop"> ... </informaltable>
{% endhighlight %}

Say we want to number all `<informaltable>` elements that have `role="elemsynop"`.

The naïve way to do that might be something like this:

{% highlight xml %}
<xsl:template match="informaltable[@role eq 'elemsynop']">
  <xsl:value-of select="
    count(preceding::informaltable[@role eq 'elemsynop']) + 1
  "/>
</xsl:template>

<!--
*** Average execution time over last 25 runs: 5.071908s (5071.908796ms)
-->
{% endhighlight %}

That works, but it's pretty slow. That's because every time the XSLT processor sees an `<informaltable>` element, it will need to walk the entire tree backwards to find all previous `<informaltable>` elements.

The most common way to count things is probably the `<xsl:number>` element. That's what it is designed for, after all. Here's an example:

{% highlight xml %}
<xsl:template match="informaltable[@role eq 'elemsynop']">
  <xsl:number count="informaltable[@role eq 'elemsynop']"
              level="any" from="/" format="1"/>
</xsl:template>

<!--
*** Average execution time over last 25 runs: 37.428838s (37428.838434ms)
-->
{% endhighlight %}

That also works, but is actually even slower than the naïve count-preceding approach. It's the slowest method by far. It's not this slow in every case, though, so if you need [any of its useful features][xsl-number], you should probably stick with `<xsl:number>`.

The fastest method for counting nodes with XSLT that I know of is to create a key and count nodes in the key. Behold:

{% highlight xml %}
<xsl:key name="informaltable-by-role"
         match="informaltable" use="@role"/>

<xsl:template match="informaltable[@role eq 'elemsynop']">
  <xsl:value-of select="
    count(key('informaltable-by-role', @role)
          [. &lt;&lt; current() or . is current()])
  "/>
</xsl:template>

<!--
*** Average execution time over last 25 runs: 440.748063ms
-->
{% endhighlight %}

This way, we only have to walk the tree once: when compiling the `informaltable-by-role` key. The information about the relative position of each node is saved when creating the key[^1] . That's why we don't need to walk the tree any more when counting the tables.

You can read the code that counts the tables as:

>Count every entry in the `informaltable-by-role` key that either:
> -  occurs in the tree before the current node, or
> - **is** the current node.

The weird `&lt;&lt;` thing is the XPath 2 [node comparison operator][xpath2-nodecomp]. It's really `<<`, which looks much nicer. You can't use angle brackets in XPath expressions in XSLT, though, so we need to escape them.

It is small sacrifice in readability. However, since it's around 91–99% faster than the traditional methods, it's probably worth the tradeoff.

## Restricting the scope

When counting things like this, you often need to count only a certain subset of elements. You might need to count only those elements that are descendants of a certain element, for instance.

You can do that with keys, too. The `key()` function also takes an optional third argument. You can use it to specify the root node for your search.

For example, if you wanted to count only those `<informaltable role="elemsynop">` elements that are inside `<refentry id="abbrev.element">`, you could do this:

{% highlight xml %}
<!-- Get the element with the @id 'abbrev.element'. -->
<xsl:variable name="top" select="key('id', 'abbrev.element')"/>

<!--
Count all <informaltable role="elemsynop"> elements that are descendants of the
element with the @id 'abbrev.element'.
-->
<xsl:value-of select="count(key('informaltable-by-role', 'elemsynop', $top))"/>
{% endhighlight %}

## Conclusion

If you're using XSLT and you need to count nodes in the XML file, instead of using the `preceding::` axis or the `<xsl:number>` element, consider creating a key and counting the nodes in the key:

{% highlight xml %}
<!--
Create an index from the @type attribute of each <pokemon> element that has one
to the element itself.
-->
<xsl:key name="pokemon" use="@type" match="pokemon[@type]"/>

<!--
Count all <pokemon type="lightning"> elements that occur in the tree before the
current node, plus the current element.
-->
<xsl:value-of select="
  count(key('pokemon', 'lightning')[. &lt;&lt; current() or . is current()])
"/>
{% endhighlight %}

It's faster.

[^1]: I don't actually know that this is true, but I assume it must do something like that because it's so much faster.

[docbook-guide]: http://sourceforge.net/p/docbook/code/HEAD/tree/trunk/defguide/zh/source/defguide.xml
[xpath2-nodecomp]: http://www.w3.org/TR/xpath20/#id-node-comparisons
[xsl-number]: http://saxonica.com/html/documentation/xsl-elements/number.html
