package com.v2ray.ang.ui

import android.annotation.SuppressLint
import android.graphics.Color
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.RecyclerView
import com.v2ray.ang.AppConfig
import com.v2ray.ang.R
import com.v2ray.ang.contracts.MainAdapterListener
import com.v2ray.ang.databinding.ItemRecyclerFooterBinding
import com.v2ray.ang.databinding.ItemRecyclerMainBinding
import com.v2ray.ang.dto.ProfileItem
import com.v2ray.ang.dto.ServerListUiItem
import com.v2ray.ang.dto.ServersCache
import com.v2ray.ang.extension.nullIfBlank
import com.v2ray.ang.handler.AngConfigManager
import com.v2ray.ang.handler.MmkvManager
import com.v2ray.ang.helper.ItemTouchHelperAdapter
import com.v2ray.ang.helper.ItemTouchHelperViewHolder
import com.v2ray.ang.viewmodel.MainViewModel
import java.util.Collections

class MainRecyclerAdapter(
    private val mainViewModel: MainViewModel,
    private val adapterListener: MainAdapterListener?
) : RecyclerView.Adapter<MainRecyclerAdapter.BaseViewHolder>(), ItemTouchHelperAdapter {
    companion object {
        private const val VIEW_TYPE_HEADER = 1
        private const val VIEW_TYPE_ITEM = 2
        private const val VIEW_TYPE_FOOTER = 3
    }

    private val doubleColumnDisplay = MmkvManager.decodeSettingsBool(AppConfig.PREF_DOUBLE_COLUMN_DISPLAY, false)
    private var data: MutableList<ServersCache> = mutableListOf()
    private var uiItems: MutableList<ServerListUiItem> = mutableListOf(ServerListUiItem.Footer)
    private var groupedDisplay = false
    private val collapsedSubscriptionIds = mutableSetOf<String>()

    @SuppressLint("NotifyDataSetChanged")
    fun setData(newData: MutableList<ServersCache>?, position: Int = -1) {
        data = newData?.toMutableList() ?: mutableListOf()
        rebuildUiItems()

        val uiPosition = uiItems.indexOfFirst { it is ServerListUiItem.Server && it.serverIndex == position }
        if (position >= 0 && uiPosition >= 0) {
            notifyItemChanged(uiPosition)
        } else {
            notifyDataSetChanged()
        }
    }

    fun setGroupedDisplay(enabled: Boolean) {
        if (groupedDisplay != enabled) {
            groupedDisplay = enabled
            collapsedSubscriptionIds.clear()
        }
        rebuildUiItems()
        notifyDataSetChanged()
    }

    override fun getItemCount() = uiItems.size

    fun getSpanSize(position: Int, spanCount: Int): Int {
        return when (uiItems.getOrNull(position)) {
            ServerListUiItem.Footer,
            is ServerListUiItem.GroupHeader -> spanCount

            is ServerListUiItem.Server,
            null -> 1
        }
    }

    override fun onBindViewHolder(holder: BaseViewHolder, position: Int) {
        val item = uiItems[position]
        if (holder is MainViewHolder && item is ServerListUiItem.Server) {
            val context = holder.itemMainBinding.root.context
            val guid = item.cache.guid
            val profile = item.cache.profile
            val serverIndex = item.serverIndex

            holder.itemView.setBackgroundColor(Color.TRANSPARENT)

            //Name address
            holder.itemMainBinding.tvName.text = profile.remarks
            holder.itemMainBinding.tvStatistics.text = getAddress(profile)
            holder.itemMainBinding.tvType.text = profile.configType.name
            holder.itemMainBinding.detailsContainer.visibility = View.VISIBLE

            //TestResult
            val aff = MmkvManager.decodeServerAffiliationInfo(guid)
            holder.itemMainBinding.tvTestResult.text = aff?.getTestDelayString().orEmpty()
            if ((aff?.testDelayMillis ?: 0L) < 0L) {
                holder.itemMainBinding.tvTestResult.setTextColor(ContextCompat.getColor(context, R.color.colorPingRed))
            } else {
                holder.itemMainBinding.tvTestResult.setTextColor(ContextCompat.getColor(context, R.color.colorPing))
            }

            //layoutIndicator
            if (guid == MmkvManager.getSelectServer()) {
                holder.itemMainBinding.layoutIndicator.setBackgroundResource(R.color.colorIndicator)
            } else {
                holder.itemMainBinding.layoutIndicator.setBackgroundResource(0)
            }

            //subscription remarks
            val subRemarks = getSubscriptionRemarks(profile)
            holder.itemMainBinding.tvSubscription.text = subRemarks
            holder.itemMainBinding.layoutSubscription.visibility = if (subRemarks.isEmpty()) View.GONE else View.VISIBLE

            //layout
            if (doubleColumnDisplay) {
                holder.itemMainBinding.layoutExpand.visibility = View.GONE
                holder.itemMainBinding.layoutShare.visibility = View.GONE
                holder.itemMainBinding.layoutEdit.visibility = View.GONE
                holder.itemMainBinding.layoutRemove.visibility = View.GONE
                holder.itemMainBinding.layoutMore.visibility = View.VISIBLE

                holder.itemMainBinding.layoutMore.setOnClickListener {
                    adapterListener?.onShare(guid, profile, serverIndex, true)
                }
                holder.itemMainBinding.layoutShare.setOnClickListener(null)
                holder.itemMainBinding.layoutEdit.setOnClickListener(null)
                holder.itemMainBinding.layoutRemove.setOnClickListener(null)
            } else {
                holder.itemMainBinding.layoutExpand.visibility = View.GONE
                holder.itemMainBinding.layoutShare.visibility = View.VISIBLE
                holder.itemMainBinding.layoutEdit.visibility = View.VISIBLE
                holder.itemMainBinding.layoutRemove.visibility = View.VISIBLE
                holder.itemMainBinding.layoutMore.visibility = View.GONE

                holder.itemMainBinding.layoutShare.setOnClickListener {
                    adapterListener?.onShare(guid, profile, serverIndex, false)
                }

                holder.itemMainBinding.layoutEdit.setOnClickListener {
                    adapterListener?.onEdit(guid, serverIndex, profile)
                }
                holder.itemMainBinding.layoutRemove.setOnClickListener {
                    adapterListener?.onRemove(guid, serverIndex)
                }
                holder.itemMainBinding.layoutMore.setOnClickListener(null)
            }

            holder.itemMainBinding.infoContainer.setOnClickListener {
                adapterListener?.onSelectServer(guid)
            }
        } else if (holder is MainViewHolder && item is ServerListUiItem.GroupHeader) {
            bindGroupHeader(holder, item)
        }

    }

    private fun bindGroupHeader(holder: MainViewHolder, header: ServerListUiItem.GroupHeader) {
        val binding = holder.itemMainBinding
        binding.tvName.text = header.title
        binding.tvStatistics.text = ""
        binding.tvType.text = ""
        binding.tvTestResult.text = ""
        binding.tvTestResult.setTextColor(ContextCompat.getColor(binding.root.context, R.color.colorPing))
        binding.layoutIndicator.setBackgroundResource(0)
        binding.layoutSubscription.visibility = View.GONE
        binding.layoutExpand.visibility = View.VISIBLE
        binding.layoutShare.visibility = View.GONE
        binding.layoutEdit.visibility = View.GONE
        binding.layoutRemove.visibility = View.GONE
        binding.layoutMore.visibility = View.GONE
        binding.detailsContainer.visibility = View.GONE
        binding.layoutShare.setOnClickListener(null)
        binding.layoutEdit.setOnClickListener(null)
        binding.layoutRemove.setOnClickListener(null)
        binding.layoutMore.setOnClickListener(null)
        binding.ivExpand.setImageResource(if (header.isExpanded) R.drawable.ic_expand_less_24dp else R.drawable.ic_arrow_drop_down)
        binding.layoutExpand.contentDescription = binding.root.context.getString(
            if (header.isExpanded) R.string.action_collapse_subscription else R.string.action_expand_subscription
        )
        binding.infoContainer.setOnClickListener {
            toggleGroup(header.subscriptionId)
        }
        binding.layoutExpand.setOnClickListener {
            toggleGroup(header.subscriptionId)
        }
    }

    /**
     * Gets the server address information
     * Hides part of IP or domain information for privacy protection
     * @param profile The server configuration
     * @return Formatted address string
     */
    private fun getAddress(profile: ProfileItem): String {
        return profile.description.nullIfBlank() ?: AngConfigManager.generateDescription(profile)
    }

    /**
     * Gets the subscription remarks information
     * @param profile The server configuration
     * @return Subscription remarks string, or empty string if none
     */
    private fun getSubscriptionRemarks(profile: ProfileItem): String {
        val subRemarks =
            if (mainViewModel.subscriptionId.isEmpty())
                MmkvManager.decodeSubscription(profile.subscriptionId)?.remarks?.firstOrNull()
            else
                null
        return subRemarks?.toString() ?: ""
    }

    private fun rebuildUiItems() {
        if (!groupedDisplay) {
            collapsedSubscriptionIds.clear()
            uiItems = data.mapIndexed { index, cache ->
                ServerListUiItem.Server(cache, index)
            }.toMutableList()
            uiItems.add(ServerListUiItem.Footer)
            return
        }

        val subscriptions = MmkvManager.decodeSubscriptions().associate { it.guid to it.subscription.remarks }
        if (subscriptions.isEmpty()) {
            uiItems = data.mapIndexed { index, cache ->
                ServerListUiItem.Server(cache, index)
            }.toMutableList()
            uiItems.add(ServerListUiItem.Footer)
            return
        }

        val grouped = data.groupBy { it.profile.subscriptionId.orEmpty() }
        collapsedSubscriptionIds.retainAll(grouped.keys)
        val items = mutableListOf<ServerListUiItem>()
        val sortedGroups = grouped.entries.sortedWith(
            compareBy<Map.Entry<String, List<ServersCache>>> { entry ->
                subscriptions[entry.key] ?: entry.key.ifBlank { "VPN" }
            }.thenBy { entry -> entry.key }
        )
        sortedGroups.forEach { (subscriptionId, servers) ->
            val title = subscriptions[subscriptionId] ?: subscriptionId.ifBlank { "VPN" }
            val expanded = !collapsedSubscriptionIds.contains(subscriptionId)
            items.add(ServerListUiItem.GroupHeader(subscriptionId, title, expanded))
            if (expanded) {
                servers.forEach { cache ->
                    val index = data.indexOfFirst { it.guid == cache.guid }
                    if (index >= 0) {
                        items.add(ServerListUiItem.Server(cache, index))
                    }
                }
            }
        }
        items.add(ServerListUiItem.Footer)
        uiItems = items
    }

    private fun toggleGroup(subscriptionId: String) {
        if (collapsedSubscriptionIds.contains(subscriptionId)) {
            collapsedSubscriptionIds.remove(subscriptionId)
        } else {
            collapsedSubscriptionIds.add(subscriptionId)
        }
        rebuildUiItems()
        notifyDataSetChanged()
    }

    fun removeServerSub(guid: String, position: Int) {
        val idx = data.indexOfFirst { it.guid == guid }
        if (idx >= 0) {
            data.removeAt(idx)
            rebuildUiItems()
            notifyDataSetChanged()
        }
    }

    fun setSelectServer(fromPosition: Int, toPosition: Int) {
        if (fromPosition < 0 && toPosition < 0) {
            notifyDataSetChanged()
            return
        }
        val fromUiPosition = uiItems.indexOfFirst { it is ServerListUiItem.Server && it.serverIndex == fromPosition }
        val toUiPosition = uiItems.indexOfFirst { it is ServerListUiItem.Server && it.serverIndex == toPosition }
        if (fromUiPosition >= 0) {
            notifyItemChanged(fromUiPosition)
        }
        if (toUiPosition >= 0) {
            notifyItemChanged(toUiPosition)
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): BaseViewHolder {
        return when (viewType) {
            VIEW_TYPE_HEADER ->
                MainViewHolder(ItemRecyclerMainBinding.inflate(LayoutInflater.from(parent.context), parent, false))

            VIEW_TYPE_ITEM ->
                MainViewHolder(ItemRecyclerMainBinding.inflate(LayoutInflater.from(parent.context), parent, false))

            else ->
                FooterViewHolder(ItemRecyclerFooterBinding.inflate(LayoutInflater.from(parent.context), parent, false))
        }
    }

    override fun getItemViewType(position: Int): Int {
        return when (uiItems[position]) {
            ServerListUiItem.Footer -> VIEW_TYPE_FOOTER
            is ServerListUiItem.GroupHeader -> VIEW_TYPE_HEADER
            is ServerListUiItem.Server -> VIEW_TYPE_ITEM
        }
    }

    open class BaseViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        fun onItemSelected() {
            itemView.setBackgroundColor(Color.LTGRAY)
        }

        fun onItemClear() {
            itemView.setBackgroundColor(0)
        }
    }

    class MainViewHolder(val itemMainBinding: ItemRecyclerMainBinding) :
        BaseViewHolder(itemMainBinding.root), ItemTouchHelperViewHolder

    class FooterViewHolder(val itemFooterBinding: ItemRecyclerFooterBinding) :
        BaseViewHolder(itemFooterBinding.root)

    override fun onItemMove(fromPosition: Int, toPosition: Int): Boolean {
        val fromItem = uiItems.getOrNull(fromPosition) as? ServerListUiItem.Server ?: return false
        val toItem = uiItems.getOrNull(toPosition) as? ServerListUiItem.Server ?: return false
        if (groupedDisplay && fromItem.cache.profile.subscriptionId != toItem.cache.profile.subscriptionId) {
            return false
        }
        val fromServerPosition = fromItem.serverIndex
        val toServerPosition = toItem.serverIndex
        mainViewModel.swapServer(fromServerPosition, toServerPosition)
        if (fromServerPosition < data.size && toServerPosition < data.size) {
            Collections.swap(data, fromServerPosition, toServerPosition)
        }
        rebuildUiItems()
        notifyDataSetChanged()
        return true
    }

    override fun onItemMoveCompleted() {
        // do nothing
    }

    override fun onItemDismiss(position: Int) {
    }
}